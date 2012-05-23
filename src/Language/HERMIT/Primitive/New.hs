{-# LANGUAGE TypeFamilies, FlexibleInstances #-}

-- Placeholder for new prims
module Language.HERMIT.Primitive.New where

import GhcPlugins

import Control.Applicative

import Language.KURE
import Language.KURE.Injection

import Language.HERMIT.HermitMonad
import Language.HERMIT.HermitEnv
import Language.HERMIT.HermitKure
import Language.HERMIT.External
import Language.HERMIT.GHC

import qualified Language.Haskell.TH as TH


promoteR'  :: Term a => RewriteH a -> RewriteH (Generic a)
promoteR' rr = rewrite $ \ c e ->  inject <$> maybe (fail "argument is not an expr") (apply rr c)  (retract e)

externals :: [External]
externals =
         [
           external "let-intro" (promoteR' . let_intro)
                [ "'let-intro v' performs E1 ==> (let v = E1 in v)" ]
         , external "var" (\ nm -> promoteR . var nm . extractR)
                [ "'var <v>' applies a rewrite to all <v>" ]
         , external "info" (promoteT info)
                [ "tell me what you know about this expression or binding" ]
         , external "expr-type" (promoteT exprTypeQueryT)
                [ "List the type (Constructor) for this expression."]
         , external "test" rewrite2query
                [ "determines if a rewrite could be successfully applied" ]
         , external "apply-rule" (promoteR . rules)
                [ "apply a named GHC rule" ]
         , external "apply-rule" rules_help
                [ "apply a named GHC rule (cmd)" ]
         ]

let_intro ::  TH.Name -> RewriteH CoreExpr
let_intro nm = rewrite $ \ _ e -> do letvar <- newVarH nm (exprType e)
                                     return $ Let (NonRec letvar e) (Var letvar)

-- Others
-- let v = E1 in E2 E3 <=> (let v = E1 in E2) E3
-- let v = E1 in E2 E3 <=> E2 (let v = E1 in E3)

-- A few Queries.

-- info currently outputs the type of the current CoreExpr
-- TODO: we need something for bindings, etc.
info :: TranslateH CoreExpr String
info = do ContextPath this <- pathT
          translate $ \ cxt e -> do
                  let hd = "Core Expr"
                      ty = "type ::= " ++ showSDoc (ppr (exprType e))
                      pa = "path :=  " ++ show (reverse this)
                      extra = "extra := " ++ case e of
                                Var v -> showSDoc (ppIdInfo v (idInfo v))
                                _ -> "{}"
                  return (unlines [hd,ty,pa,extra])


exprTypeQueryT :: TranslateH CoreExpr String
exprTypeQueryT = liftT $ \ e -> case e of
                                  Var _        -> "Var"
                                  Type _       -> "Type"
                                  Lit _        -> "Lit"
                                  App _ _      -> "App"
                                  Lam _ _      -> "Lam"
                                  Let _ _      -> "Let"
                                  Case _ _ _ _ -> "Case"
                                  Cast _ _     -> "Cast"
                                  Tick _ _     -> "Tick"
                                  Coercion _   -> "Coercion"

rewrite2query :: RewriteH Core -> TranslateH Core String
rewrite2query r = f <$> testT r
  where
    f True  = "Rewrite would succeed."
    f False = "Rewrite would fail."

var :: TH.Name -> RewriteH CoreExpr -> RewriteH CoreExpr
var _ n = idR -- bottomupR (varR (\ n -> ()) ?

rules :: String -> RewriteH CoreExpr
rules r = rewrite $ \ c e -> do
        liftIO $ print ("rules",r)
        return e

rules_help :: RewriteH Core
rules_help = rewrite $ \ _ e -> do { liftIO (print "apply with no args") ; return (e :: Core) }

