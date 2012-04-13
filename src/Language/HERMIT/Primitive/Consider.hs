{-# LANGUAGE TypeFamilies, FlexibleInstances #-}

module Language.HERMIT.Primitive.Consider where

import GhcPlugins
import qualified Data.Map as Map
import Data.List
import Data.Maybe
import Data.Monoid

import Language.HERMIT.Types
import Language.HERMIT.External
import Language.HERMIT.KURE
import Language.HERMIT.HermitEnv

import qualified Language.Haskell.TH as TH

import Debug.Trace

externals :: External
externals = external "consider" (\ nm -> consider nm `glueL` promoteL)
        [ "'consider <v>' focuses into the rhs of the binding <v>"
        ]

-- Focus on the Rhs of a bindings
consider :: TH.Name -> Lens (Generic CoreExpr) CoreExpr
consider nm = do
        First cxtpaths <- alltdU (promoteU $ findPathTo nm)
        case cxtpaths of
          Just cxtpath -> do
             path <- rmPrefix cxtpath
             manyL path `glueL` extractL
          Nothing -> failL "no paths to consideration"


-- Take a ContextPath (always from the *Root*) from a deeper location,
-- and return the Path to *this* node.
rmPrefix :: (Term a, a ~ Core) => ContextPath -> Translate (Generic a) Path
rmPrefix (ContextPath path) = do
        ContextPath this <- pathT
        if this `isSuffixOf` path then return $ Path $ drop (length this) $ reverse path
                                else fail "rmPrefix failure"

findPathTo :: TH.Name -> Translate CoreBind (First ContextPath)
findPathTo nm = translate $ \ (Context c e) -> case e of
                  NonRec v _
                    | nm `cmpName` (idName v) ->
                        return $ let (ContextPath ps) = hermitBindingPath c
                                 in First (Just $ ContextPath (0 : ps))
                  Rec bds -> do
                    let res =
                            [ let (ContextPath ps) = hermitBindingPath c
                               in ContextPath (i : ps)
                            | ((v,e),i) <- bds `zip` [0..]
                            , nm `cmpName` (idName v)
                            ]
                    case res of
                      [r] -> return $ First $ Just r
                      _   -> fail "name not found"
                  _ -> fail $ "name " ++ show nm ++ " not found"


-- Hacks till we can find the correct way of doing these.
cmpName :: TH.Name -> Name -> Bool
cmpName th_nm ghc_nm
        | trace (show (TH.nameBase th_nm,occNameString (nameOccName ghc_nm))) False = undefined
        | TH.nameBase th_nm == occNameString (nameOccName ghc_nm) = True
        | otherwise = False