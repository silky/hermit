{-# LANGUAGE KindSignatures, GADTs #-}
-- The main namespace. Things tend to be untyped, because the API is accessed via (untyped) names.

module Language.HERMIT.Dictionary where

import Prelude hiding (lookup)

import qualified Data.Map as M
import Data.Char
import Data.Dynamic

import Control.Monad (liftM2)

import GhcPlugins

import qualified Language.Haskell.TH as TH

import Language.KURE

import Language.HERMIT.HermitExpr
import Language.HERMIT.HermitKure
import Language.HERMIT.Kernel
import Language.HERMIT.External

import qualified Language.HERMIT.Primitive.Command as Command
import qualified Language.HERMIT.Primitive.Kure as Kure
import qualified Language.HERMIT.Primitive.Consider as Consider
import qualified Language.HERMIT.Primitive.Inline as Inline
import qualified Language.HERMIT.Primitive.Case as Case
import qualified Language.HERMIT.Primitive.Subst as Subst
import qualified Language.HERMIT.Primitive.Local as Local
import qualified Language.HERMIT.Primitive.New as New

import Debug.Trace
--------------------------------------------------------------------------

prim_externals :: [External]
prim_externals =    Command.externals
                 ++ Kure.externals
                 ++ Consider.externals
                 ++ Inline.externals
                 ++ Case.externals
                 ++ Subst.externals
                 ++ Local.externals
                 ++ New.externals

all_externals :: [External]
all_externals =    prim_externals
                ++ [ external "bash" (promoteR bash) bashHelp .+ MetaCmd
                   ]

dictionary :: M.Map String [Dynamic]
dictionary = toDictionary all_externals

help :: [External] -> [String]
help = concatMap snd . M.toList . toHelp

--------------------------------------------------------------------------

-- The union of all possible results from a "well-typed" commands, from this dictionary.

interpExprH :: ExprH -> Either String KernelCommand
interpExprH expr =
        case interpExpr' expr of
          Left msg  -> Left msg
          Right dyn -> runInterp dyn
             [ Interp $ \ (KernelCommandBox cmd)      -> Right cmd
             , Interp $ \ (RewriteCoreBox rr)         -> Right $ Apply rr
             , Interp $ \ (TranslateCoreStringBox tt) -> Right $ Query tt
             , Interp $ \ (LensCoreCoreBox l)         -> Right $ PushFocus l
             , Interp $ \ (IntBox i)                  -> Right $ PushFocus $ chooseL i
             , Interp $ \ (Help cat)                  -> Left  $ unlines $ help
                                                               $ maybe all_externals (\c -> filter (`hasTag` c) all_externals) cat
             ]
             (Left "interpExpr: bad type of expression")

data Interp :: * -> * where
   Interp :: Typeable a => (a -> b) -> Interp b

runInterp :: [Dynamic] -> [Interp b] -> b -> b
runInterp dyns interps bad = head $
             [f a
             | Interp f <- interps
             , Just a <- map fromDynamic dyns
             ] ++ [ bad ]



--------------------------------------------------------------------------

interpExpr :: ExprH -> Either String Dynamic
interpExpr expr =
        case interpExpr' expr of
          Left msg -> Left msg
          Right [r] -> Right r
          Right []  -> Left $ "no valid interpretation"
          Right _   -> Left $ "multiple valid interpretations"

-- Why doesn't help immediately drop a Left here? Why bother making a Help command?
interpExpr' :: ExprH -> Either String [Dynamic]
interpExpr' (SrcName str) = return [ toDyn $ NameBox $ TH.mkName str ]
interpExpr' (CmdName str)
  | all isDigit str                     = return [ toDyn $ IntBox $ read str ]
  | ("help",cat) <- break isSpace str   = case dropWhile isSpace cat of
                                            "list" -> Left $ unlines $ map show [minBound..(maxBound :: CmdCategory)]
                                            cat'   -> return [ toDyn $ Help $ readMaybe cat' ]
  | Just dyn <- M.lookup str dictionary = return dyn
  | otherwise                           = Left $ "Unrecognised command: " ++ show str
interpExpr' (StrName str)               = return [ toDyn $ StringBox $ str ]
interpExpr' (AppH e1 e2) = dynAppMsg (interpExpr' e1) (interpExpr' e2)

dynAppMsg :: Either String [Dynamic] -> Either String [Dynamic] -> Either String [Dynamic]
dynAppMsg f x = liftM2 dynApply' f x >>= return
   where
           dynApply' :: [Dynamic] -> [Dynamic] -> [Dynamic]
           dynApply' fs xs = [ r | f <- fs, x <- xs, Just r <- return (dynApply f x)]

-- Surely this exists somewhere! Replace it if so.
readMaybe :: (Read a) => String -> Maybe a
readMaybe s = case reads s of
                [(x,rest)] | all isSpace rest -> Just x
                _ -> Nothing

--------------------------------------------------------------------------

-- Runs every command tagged with 'Bash' with anybuR,
-- if any of them succeed, then it tries all of them again.
-- Only fails if all of them fail the first time.
bash :: RewriteH (Generic CoreExpr)
bash = repeatR $ orR [ maybe (fail "bash: fromDynamic failed") (anybuR . unbox)
                       $ fromDynamic $ externFun $ cmd
                     | cmd <- all_externals, cmd `hasTag` Bash ]

bashHelp :: [String]
bashHelp = "Bash runs the following commands:"
           : (help $ filter (`hasTag` Bash) all_externals)
