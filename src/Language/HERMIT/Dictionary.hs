{-# LANGUAGE KindSignatures, GADTs, ScopedTypeVariables #-}
-- The main namespace. Things tend to be untyped, because the API is accessed via (untyped) names.

module Language.HERMIT.Dictionary where

import Prelude hiding (lookup)

import Data.Default (def)
import Data.Dynamic
import Data.List
import qualified Data.Map as M
import Data.Maybe

import GhcPlugins

import Language.HERMIT.Kure
import Language.HERMIT.External

--import qualified Language.HERMIT.Primitive.Command as Command
import qualified Language.HERMIT.Primitive.Kure as Kure
import qualified Language.HERMIT.Primitive.Consider as Consider
import qualified Language.HERMIT.Primitive.Inline as Inline
import qualified Language.HERMIT.Primitive.Subst as Subst
import qualified Language.HERMIT.Primitive.Local as Local
import qualified Language.HERMIT.Primitive.New as New
import qualified Language.HERMIT.Primitive.Debug as Debug
import qualified Language.HERMIT.Primitive.GHC as GHC


import Language.HERMIT.PrettyPrinter
import qualified Language.HERMIT.PrettyPrinter.AST as AST
import qualified Language.HERMIT.PrettyPrinter.Clean as Clean
import qualified Language.HERMIT.PrettyPrinter.GHC as GHCPP


--------------------------------------------------------------------------

prim_externals :: ModGuts -> [External]
prim_externals modGuts
               =    Kure.externals
                 ++ Consider.externals
                 ++ Inline.externals
                 ++ Subst.externals
                 ++ Local.externals
                 ++ Debug.externals
                 ++ New.externals modGuts

-- The GHC.externals here is a bit of a hack. Not sure about this
all_externals :: [External] -> ModGuts -> [External]
all_externals my_externals guts = prim_externals guts ++ my_externals ++ GHC.externals guts

-- create the dictionary
dictionary :: [External] -> M.Map String [Dynamic]
dictionary externs = toDictionary externs'
  where
        msg = layoutTxt 60 (map (show . fst) dictionaryOfTags)
        externs' = externs ++
                map (.+ Shell)
                [ external ":help" (help_command externs' "help")
                    [ "(this message)" ] .+ Help
                , external ":help" (help_command externs')
                    ([ ":help <command>|<category>|categories|all|<search-string>"
                     , "displays help about a command or category."
                     , "Multiple items may match."
                     , ""
                     , "categories: " ++ head msg
                     ] ++ (map ("            " ++) (tail msg)))  .+ Help
                , bashExternal externs  .+ Eval .+ Deep .+ Loop
                ]

--------------------------------------------------------------------------
-- The pretty printing dictionaries
pp_dictionary :: M.Map String (PrettyOptions -> PrettyH Core)
pp_dictionary = M.fromList
        [ ("clean",  Clean.corePrettyH)
        , ("ast",    AST.corePrettyH)
        , ("ghc",    GHCPP.corePrettyH)
        ]

-- each pretty printer can suggest some options
pp_opt_dictionary :: M.Map String PrettyOptions
pp_opt_dictionary = M.fromList
        [ ("clean", def)
        , ("ast",  def)
        , ("ghc",  def)
        ]


--------------------------------------------------------------------------

make_help :: [External] -> [String]
make_help = concatMap snd . M.toList . toHelp

help_command :: [External] -> String -> String
help_command externals m
        | [(cat :: CmdTag,"")] <- reads m
        = unlines $ make_help $ filter (tagMatch cat) externals
help_command externals "all"
        = unlines $ make_help $ externals
help_command externals "categories" = unlines $
                [ "categories" ] ++
                [ "----------" ] ++
                [ txt ++ " " ++ take (16 - length txt) (repeat '.') ++ " " ++ desc
                | (cmd,desc) <- dictionaryOfTags
                , let txt = show cmd
                ]

help_command externals m = unlines $ make_help $ pathPrefix m
    where pathPrefix p = filter (isInfixOf p . externName) externals

layoutTxt :: Int -> [String] -> [String]
layoutTxt n (w1:w2:ws) | length w1 + length w2 >= n = w1 : layoutTxt n (w2:ws)
                       | otherwise = layoutTxt n ((w1 ++ " " ++ w2) : ws)
layoutTxt n other = other


help :: [External] -> Maybe String -> Maybe String -> String
-- 'help ls' case
help externals Nothing (Just "ls") = help externals (Just "ls") Nothing
-- 'help' or 'help <search string>' case
help externals Nothing m = unlines $ make_help $ maybe externals pathPrefix m
    where pathPrefix p = filter (isInfixOf p . externName) externals
-- 'help ls <path>' case
help externals (Just "ls") m = unlines $ map toLine groups
    where fixHyphen p | last p == '-' = p
                      | otherwise     = p ++ "-"
          optParens s | null s = ""
                      | otherwise = "  (" ++ s ++ ")"
          prefix = maybe "" fixHyphen m
          groups = groupBy ((==) `on` fst)
                 $ sortBy (compare `on` fst)
                   [ (fst $ span (/='-') $ drop (length prefix) n, n)
                   | n <- map externName externals, prefix `isPrefixOf` n ]
          toLine [] = ""
          toLine ((d,cmd):r) = d ++ optParens (intercalate ", " [ cmd' | cmd' <- cmd : map snd r, cmd' /= d ])
help _ _ _ = error "bad help arguments"

--------------------------------------------------------------------------

-- TODO: supply map of command-name -> arguments?
-- otherwise fromDynamic will fail for any rewrite that takes arguments.
metaCmd :: (Tag a)
        => String                             -- ^ name of the command
        -> [External]                         -- ^ universe of commands to search
        -> a                                  -- ^ tag matching predicate
        -> ([RewriteH Core] -> RewriteH Core) -- ^ means to combine the matched rewrites
        -> [String]                           -- ^ help text preamble
        -> External
metaCmd name externs p combine hlp = external name (combine rws) (hlp ++ concat helps)
    where (rws, helps) = unzip [ (rw, externName e : externHelp e)
                               | e <- externs
                               , tagMatch p e
                               , Just rw <- [fmap unbox $ fromDynamic $ externFun e] ]

-- Runs every command tagged with 'Bash' with innermostR (fix point anybuR),
-- if any of them succeed, then it tries all of them again.
-- Only fails if all of them fail the first time.
-- TODO: We need to think harder about bash.
bashExternal :: [External] -> External
bashExternal es = metaCmd "bash" es (Eval .& (notT Loop)) (innermostR . orR)
                          [ "Iteratively apply the following rewrites until nothing changes." ]

bash :: [External] -> RewriteH Core
bash = unbox . fromJust . fromDynamic . externFun . bashExternal
