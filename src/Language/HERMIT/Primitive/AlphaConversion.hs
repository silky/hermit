{-# LANGUAGE TypeFamilies, FlexibleContexts #-}
-- TODO: remove this module
module Language.HERMIT.Primitive.Subst where

import GhcPlugins hiding (empty)

import Control.Arrow

import Language.HERMIT.Context
import Language.HERMIT.Monad
import Language.HERMIT.Kure
import Language.HERMIT.External
import Language.HERMIT.Primitive.GHC(freeVarsT, substR)  -- coreExprFreeIds

import Language.HERMIT.Primitive.Common

import qualified Language.Haskell.TH as TH

import Prelude hiding (exp)

externals :: [External]
externals = map (.+ Deep)
         [  external "alpha" alpha
               [ "renames the bound variables at the current node."]
         ,  external "alpha-lam" (promoteExprR . alphaLam . Just)
               [ "renames the bound variable in a Lambda expression to the given name."]
         ,  external "alpha-lam" (promoteExprR $ alphaLam Nothing)
               [ "renames the bound variable in a Lambda expression."]
         ,  external "alpha-case-binder" (promoteExprR . alphaCaseBinder . Just)
               [ "renames the binder in a Case expression to the given name."]
         ,  external "alpha-case-binder" (promoteExprR $ alphaCaseBinder Nothing)
               [ "renames the binder in a Case expression."]
         ,  external "alpha-alt" (promoteAltR alphaAlt)
               [ "renames all binders in a Case alternative."]
         ,  external "alpha-case" (promoteExprR alphaCase)
               [ "renames all binders in a Case alternative."]
         ,  external "alpha-let" (promoteExprR . alphaLetOne . Just)
               [ "renames the bound variable in a Let expression with one binder to the given name."]
         ,  external "alpha-let" (promoteExprR alphaLet)
               [ "renames the bound variables in a Let expression."]
         ,  external "alpha-top" (promoteProgramR . alphaConsOne . Just)
               [ "renames the bound variable in a top-level binding with one binder to the given name."]
         ,  external "alpha-top" (promoteProgramR alphaCons)
               [ "renames the bound variables in a top-level binding."]

         , external "unshadow" (unshadow :: RewriteH Core)
                [ "Rename local variable with manifestly unique names (x, x0, x1, ...)"]

         ]


{-
substR :: Id -> CoreExpr -> RewriteH Core
substR v e = promoteExprR (substVarR v e) <+ substNonVarR v e

substVarR :: Id -> CoreExpr -> RewriteH CoreExpr
substVarR v e = whenM (varT (==v)) (return e)

-- This definition contains themain logic of the substitution algorithm
substNonVarR :: Id -> CoreExpr -> RewriteH Core
substNonVarR v e = let fvs = coreExprFreeIds e in
                   do bs <- arr idsBound
                      if v `elem` bs
                        then substWhereBinderOutOfScopeR v e
                        else let xs = fvs `intersect` bs
                              in andR (map alphaRenameId xs) >>> anyR (substR v e)
                                 -- rename any binders that would capture free variables in the expression to
                                 -- be substituted in, then descend and continue substituting
  where
    alphaRenameId :: Id -> RewriteH Core
    alphaRenameId i =  promoteR (alphaConsNonRec Nothing <+ alphaConsRecId Nothing i)
                    <+ promoteR (alphaAltId Nothing i)
                    <+ promoteR (alphaLam Nothing <+ (alphaLetNonRec Nothing <+ alphaLetRecId Nothing i) <+ alphaCaseBinder Nothing)

-- TODO: There is overlap between this and the functions in Common.hs.  Maybe merge?  Maybe not.
-- | All the identifiers bound /at this level/.
idsBound :: Core -> [Id]
idsBound (ModGutsCore _)      = []
idsBound (BindCore _)         = [] -- too low level, should have been dealt with higher up
idsBound (DefCore _)          = [] -- too low level, should have been dealt with higher up
idsBound (AltCore (_,vs,_))   = vs
idsBound (ProgramCore p)      = case p of
                                  []    -> []
                                  (b:_) -> bindings b
idsBound (ExprCore e)         = case e of
                                  Lam v _      -> [v]
                                  Let b _      -> bindings b
                                  Case _ v _ _ -> [v]  -- alternatives are dealt with lower down
                                  _            -> []

-- | For situations where we have a node containing a binder /and/ a child that is not in scope of that binder,
--   this substitutes into that out-of-scope child.
substWhereBinderOutOfScopeR :: Id -> CoreExpr -> RewriteH Core
substWhereBinderOutOfScopeR v e =  promoteR (consBindAllR substNonRecR idR)
                                <+ promoteR (letAllR substNonRecR idR <+ caseAllR (extractR (substR v e)) (const idR))
  where
    substNonRecR :: RewriteH CoreBind
    substNonRecR = nonRecR (extractR (substR v e))

-}
-----------------------------------------------------------------------

-----------------------------------------------------------------------
--
-- freshNameGen is a function used in conjunction with cloneIdH, which clones an existing Id.
-- But, what name should the new Id have?
-- cloneIdH generates a new Unique -- so we are positive that the new Id will be new,
-- but freshNameGen tries to assign a Name that will be meaningful to the user, and
-- not shadow other names in scope.
-- So,  we start with the name of the original Id, and add an integer suffix
--  x  goes to x0 or x1 or ...
-- and we do not want this newly generated name to shadow either:
-- 1.  Any free variable name in the active Expr; or
-- 2.  Any bound variables in context.

visibleIds :: TranslateH CoreExpr [Id]
visibleIds = do ctx <- contextT
                frees <- freeVarsT
                return $ frees ++ (listBindings ctx)

freshNameGen :: (Maybe TH.Name) -> [Id] -> (String -> String)
freshNameGen newName idsToAvoid =
        case newName of
          Just name -> const (show name)
          Nothing   -> inventNames idsToAvoid

freshNameGenT :: (Maybe TH.Name) -> TranslateH CoreExpr (String -> String)
freshNameGenT newName =
        case newName of
          Just name -> return $ const (show name)
          Nothing -> do idsToAvoid <- visibleIds
                        return $ freshNameGen Nothing idsToAvoid

{-
inventNames curr old | trace (show ("inventNames",names,old)) False = undefined
    where
            names = map getOccString curr
-}

inventNames :: [Id] -> String -> String
inventNames curr old = head
                     [ nm
                     | nm <- [ old ++ show uq | uq <- [0..] :: [Int] ]
                     , nm `notElem` names
                     ]
   where
           names = map getOccString curr

-- | Arguments are the original identifier and the replacement identifier, respectively.
renameIdR :: (Injection a Core, Generic a ~ Core) => Id -> Id -> RewriteH a
renameIdR v v' = extractR $ tryR $ substR v (Var v')

-- | Given an identifier to replace, and a replacement, produce an 'Id' @->@ 'Id' function that
--   acts as in identity for all 'Id's except the one to replace, for which it returns the replacment.
--   Don't export this, it'll likely just cause confusion.
replaceId :: Id -> Id -> (Id -> Id)
replaceId v v' i = if v == i then v' else i

-----------------------------------------------------------------------

-- | Alpha rename a lambda binder.  Optionally takes a suggested new name.
alphaLam :: Maybe TH.Name -> RewriteH CoreExpr
alphaLam mn = setFailMsg (wrongFormForAlpha "Lam v e") $
              do (v, nameModifier) <- lamT (freshNameGenT mn) (,)
                 v' <- constT (cloneIdH nameModifier v)
                 lamT (renameIdR v v') (\ _ -> Lam v')

-----------------------------------------------------------------------

-- | Alpha rename a case binder.  Optionally takes a suggested new name.
alphaCaseBinder :: Maybe TH.Name -> RewriteH CoreExpr
alphaCaseBinder mn = setFailMsg (wrongFormForAlpha "Case e v ty alts") $
                     do Case _ v _ _ <- idR
                        nameModifier <- freshNameGenT mn
                        v' <- constT (cloneIdH nameModifier v)
                        caseT idR (\ _ -> renameIdR v v') (\ e _ t alts -> Case e v' t alts)

-----------------------------------------------------------------------

-- | Rename the specified identifier in a case alternative.  Optionally takes a suggested new name.
alphaAltId :: Maybe TH.Name -> Id -> RewriteH CoreAlt
alphaAltId mn v = do nameModifier <- altT (freshNameGenT mn) (\ _ _ nameGen -> nameGen)
                     v' <- constT (cloneIdH nameModifier v)
                     altT (renameIdR v v') (\ con vs e -> (con, map (replaceId v v') vs, e))

-- | Rename all identifiers bound in a case alternative.
alphaAlt :: RewriteH CoreAlt
alphaAlt = setFailMsg (wrongFormForAlpha "(con,vs,e)") $
           do (_, vs, _) <- idR
              andR $ map (alphaAltId Nothing) vs

-----------------------------------------------------------------------

-- | Rename all identifiers bound in a case expression.
alphaCase :: RewriteH CoreExpr
alphaCase = alphaCaseBinder Nothing >+> caseAnyR (fail "") (const alphaAlt)

-----------------------------------------------------------------------

-- | Alpha rename a non-recursive let binder.  Optionally takes a suggested new name.
alphaLetNonRec :: Maybe TH.Name -> RewriteH CoreExpr
alphaLetNonRec mn = setFailMsg (wrongFormForAlpha "Let (NonRec v e1) e2") $
                    do (v, nameModifier) <- letNonRecT idR (freshNameGenT mn) (\ v _ nameMod -> (v, nameMod))
                       v' <- constT (cloneIdH nameModifier v)
                       letNonRecT idR (renameIdR v v') (\ _ e1 e2 -> Let (NonRec v' e1) e2)

-- | Rename the specified identifier bound in a recursive let.  Optionally takes a suggested new name.
alphaLetRecId :: Maybe TH.Name -> Id -> RewriteH CoreExpr
alphaLetRecId mn v = setFailMsg (wrongFormForAlpha "Let (Rec bs) e") $
                     do Let (Rec {}) _ <- idR
                        ctx <- contextT
                         -- Cannot use freshNameGen directly, because we want to include
                         -- free variables from every bound expression, in the name generation function
                         -- as a result we must replicate the essence of freshNameGen in the next few lines
                        frees <- letRecDefT (\ _ -> freeVarsT) freeVarsT (\ bindFrees exprFrees -> (concat (map snd bindFrees)) ++ exprFrees)
                        let nameGen = case mn of
                                        Just name -> const (show name)
                                        Nothing -> inventNames (frees ++ (listBindings ctx))
                        v' <- constT (cloneIdH nameGen v)

                        letRecDefT (\ _ -> renameIdR v v') (renameIdR v v') (\ bs e -> Let (Rec $ (map.first) (replaceId v v') bs) e)

-- | Rename all identifiers bound in a recursive let.
alphaLetRec :: RewriteH CoreExpr
alphaLetRec = setFailMsg (wrongFormForAlpha "Let (Rec bs) e") $
              do Let (Rec bs) _ <- idR
                 andR $ map (alphaLetRecId Nothing . fst) bs

-- | Rename the identifier bound in a recursive let with a single recursively bound identifier.  Optionally takes a suggested new name.
alphaLetRecOne :: Maybe TH.Name -> RewriteH CoreExpr
alphaLetRecOne mn = setFailMsg (wrongFormForAlpha "Let (Rec [(v,e1)]) e2") $
                    do Let (Rec [(v, _)]) _ <- idR
                       alphaLetRecId mn v

-- | Rename the identifier bound in a let with a single bound identifier.  Optionally takes a suggested new name.
alphaLetOne :: Maybe TH.Name -> RewriteH CoreExpr
alphaLetOne mn = alphaLetNonRec mn <+ alphaLetRecOne mn

-- | Rename all identifiers bound in a Let.
alphaLet :: RewriteH CoreExpr
alphaLet = alphaLetRec <+ alphaLetNonRec Nothing

-----------------------------------------------------------------------

-- | Alpha rename a non-recursive top-level binder.  Optionally takes a suggested new name.
alphaConsNonRec :: Maybe TH.Name -> RewriteH CoreProgram
alphaConsNonRec mn = setFailMsg (wrongFormForAlpha "NonRec v e : prog") $
                     do NonRec v _ : _ <- idR
                        nameModifier <- consNonRecT (freshNameGenT mn) idR (\ _ nameGen _ -> nameGen)
                        v' <- constT (cloneIdH nameModifier v)
                        consNonRecT idR (renameIdR v v') (\ _ e1 e2 -> NonRec v' e1 : e2)

-- | Rename the specified identifier bound in a recursive top-level binder.  Optionally takes a suggested new name.
alphaConsRecId :: Maybe TH.Name -> Id -> RewriteH CoreProgram
alphaConsRecId mn v = setFailMsg (wrongFormForAlpha "Rec bs : prog") $
                      do Rec {} : _ <- idR
                         -- Cannot use freshNameGen directly, because we want to include
                         -- free variables from every bound expression, in the name generation function
                         -- as a result we must replicate the essence of freshNameGen in the next few lines
                         ctx <- contextT
                         frees <- consRecDefT (\ _ -> freeVarsT) idR (\ frees _ -> concat (map snd frees))
                         let nameGen = case mn of
                                         Just name -> const (show name)
                                         Nothing -> inventNames (frees ++ (listBindings ctx))
                         v' <- constT (cloneIdH nameGen v)
                         consRecDefT (\ _ -> renameIdR v v') (renameIdR v v') (\ bs e -> Rec ((map.first) (replaceId v v') bs) : e)

-- | Rename all identifiers bound in a recursive top-level binder.
alphaConsRec :: RewriteH CoreProgram
alphaConsRec = setFailMsg (wrongFormForAlpha "Rec bs : prog") $
               do Rec bs : _ <- idR
                  andR $ map (alphaConsRecId Nothing . fst) bs

-- | Rename the identifier bound in a recursive top-level binder with a single recursively bound identifier.  Optionally takes a suggested new name.
alphaConsRecOne :: Maybe TH.Name -> RewriteH CoreProgram
alphaConsRecOne mn = setFailMsg (wrongFormForAlpha "Rec [(v,e)] : prog") $
                     do Rec [(v, _)] : _ <- idR
                        alphaConsRecId mn v

-- | Rename the identifier bound in a top-level binder with a single bound identifier.  Optionally takes a suggested new name.
alphaConsOne :: Maybe TH.Name -> RewriteH CoreProgram
alphaConsOne mn = alphaConsNonRec mn <+ alphaConsRecOne mn

-- | Rename all identifiers bound in a Let.
alphaCons :: RewriteH CoreProgram
alphaCons = alphaConsRec <+ alphaConsNonRec Nothing

-----------------------------------------------------------------------

-- | Alpha rename any bindings at this node.  Note: does not rename case alternatives unless invoked on the alternative.
alpha :: RewriteH Core
alpha = setFailMsg "Cannot alpha-rename here." $
           promoteExprR (alphaLam Nothing <+ alphaCaseBinder Nothing <+ alphaLet)
        <+ promoteProgramR alphaCons

unshadow :: RewriteH Core
unshadow = anytdR (promoteExprR (alphaLam Nothing <+ alphaCaseBinder Nothing <+ alphaLet))

-----------------------------------------------------------------------

wrongFormForAlpha :: String -> String
wrongFormForAlpha s = "Cannot alpha-rename: " ++ wrongExprForm s