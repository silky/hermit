module Language.HERMIT.Primitive.GHC where

import GhcPlugins hiding (freeVars,empty)

import Control.Arrow
import qualified Data.Map as Map

import Language.HERMIT.HermitKure
import Language.HERMIT.External



------------------------------------------------------------------------

externals :: ModGuts -> [External]
externals modGuts = map (.+ GHC)
         [ external "let-subst" (promoteR letSubstR :: RewriteH Core)
                [ "Let substitution [via GHC]"
                , "let x = E1 in E2, where x is free is E2 ==> E2[E1/x], fails otherwise"
                , "only matches non-recursive lets" ]                           .+ Local .+ Eval
         , external "freevars" (promoteT freeIdsQuery :: TranslateH Core String)
                [ "List the free variables in this expression [via GHC]" ]
         , external "deshadow-binds" (promoteR deShadowBindsR :: RewriteH Core)
                [ "Deshadow a program [via GHC]" ]
         , external "apply-rule" (promoteR . rules rulesEnv :: String -> RewriteH Core)
                [ "apply a named GHC rule" ]
         , external "apply-rule" (rules_help rulesEnv)
                [ "list rules that can be used" ]
         ]
  where
          rulesEnv :: Map.Map String (RewriteH CoreExpr)
          rulesEnv = rulesToEnv (mg_rules modGuts)

------------------------------------------------------------------------

letSubstR :: RewriteH CoreExpr
letSubstR = contextfreeT $ \ exp -> case exp of
      Let (NonRec b be) e
         | isId b    -> let empty = mkEmptySubst (mkInScopeSet (exprFreeVars exp))
                            sub   = extendSubst empty b be
                         in return $ substExpr (text "letSubstR") sub e
      Let (NonRec b (Type bty)) e
         | isTyVar b -> let empty = mkEmptySubst (mkInScopeSet (exprFreeVars exp))
                            sub = extendTvSubst empty b bty
                         in return $ substExpr (text "letSubstR") sub e
      _ -> fail "LetSubst failed. Expr is not a (non-recursive) Let."

------------------------------------------------------------------------

-- output a list of all free variables in the Expr.
freeIdsQuery :: TranslateH CoreExpr String
freeIdsQuery = freeIdsT >>^ (("FreeVars are: " ++) . show . map (showSDoc.ppr))

freeIdsT :: TranslateH CoreExpr [Id]
freeIdsT = arr freeIds

freeVarsT :: TranslateH CoreExpr [Id]
freeVarsT = arr freeVars

-- note: exprFreeVars get *all* free variables, including types
-- note: shadows the freeVars in GHC that operates on the AnnCore.
-- TODO: we should rename this.
freeVars :: CoreExpr -> [Id]
freeVars  = uniqSetToList . exprFreeVars

-- note: exprFreeIds is only value-level free variables
freeIds :: CoreExpr -> [Id]
freeIds  = uniqSetToList . exprFreeIds

------------------------------------------------------------------------

-- | [from GHC documentation] De-shadowing the program is sometimes a useful pre-pass.
-- It can be done simply by running over the bindings with an empty substitution,
-- becuase substitution returns a result that has no-shadowing guaranteed.
--
-- (Actually, within a single /type/ there might still be shadowing, because
-- 'substTy' is a no-op for the empty substitution, but that's probably OK.)
deShadowBindsR :: RewriteH CoreProgram
deShadowBindsR = arr deShadowBinds

------------------------------------------------------------------------
{-
lookupRule :: (Activation -> Bool)	-- When rule is active
	    -> IdUnfoldingFun		-- When Id can be unfolded
            -> InScopeSet
	    -> Id -> [CoreExpr]
	    -> [CoreRule] -> Maybe (CoreRule, CoreExpr)
-}

rulesToEnv :: [CoreRule] -> Map.Map String (RewriteH CoreExpr)
rulesToEnv rs = Map.fromList
        [ ( unpackFS (ruleName r), rulesToRewriteH [r] )
        | r <- rs
        ]

rulesToRewriteH :: [CoreRule] -> RewriteH CoreExpr
rulesToRewriteH rs = contextfreeT $ \ e ->
        -- First, we normalize the lhs, so we can match it
        let (Var fn,args) = collectArgs e
        -- Question: does this include Id's, or Var's (which include type names)
        -- Assumption: Var's.
            in_scope = mkInScopeSet (mkVarEnv [ (v,v) | v <- freeVars e ])
        -- The rough_args are just an attempt to try eliminate silly things
        -- that will never match
            rough_args = map (const Nothing) args   -- rough_args are never used!!! FIX ME!
        -- Finally, we try match the rules
         in case lookupRule (const True) (const NoUnfolding) in_scope fn args rs of
              Nothing      -> fail "rule not matched"
              Just (_,e')  -> return e'

rules :: Map.Map String (RewriteH CoreExpr) -> String -> RewriteH CoreExpr
rules mp r = case Map.lookup r mp of
               Nothing -> fail $ "failed to find rule: " ++ show r
               Just rr -> rr

rules_help :: Map.Map String (RewriteH CoreExpr) -> String
rules_help env = show (Map.keys env)



