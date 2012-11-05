module Language.HERMIT.Primitive.FixPoint where

import GhcPlugins as GHC hiding (varName)

import Control.Arrow

import Language.HERMIT.Core
import Language.HERMIT.Context
import Language.HERMIT.Monad
import Language.HERMIT.Kure
import Language.HERMIT.External
import Language.HERMIT.GHC
import Language.HERMIT.Primitive.GHC
import Language.HERMIT.Primitive.Common
import Language.HERMIT.Primitive.Local
import Language.HERMIT.Primitive.AlphaConversion
import Language.HERMIT.Primitive.New -- TODO: Sort out heirarchy
-- import Language.HERMIT.Primitive.Debug

import qualified Language.Haskell.TH as TH



externals ::  [External]
externals = map ((.+ Experiment) . (.+ TODO))
         [ external "fix-intro" (promoteDefR fixIntro :: RewriteH Core)
                [ "rewrite a recursive binding into a non-recursive binding using fix" ]
         , external "fix-spec" (promoteExprR fixSpecialization :: RewriteH Core)
                [ "specialize a fix with a given argument"] .+ Shallow
         , external "ww-fac-test" ((\ wrap unwrap -> promoteExprR $ workerWrapperFacTest wrap unwrap) :: TH.Name -> TH.Name -> RewriteH Core)
                [ "Under construction "
                ] .+ Introduce .+ Context .+ Experiment .+ PreCondition
         , external "ww-split-test" ((\ wrap unwrap -> promoteDefR $ workerWrapperSplitTest wrap unwrap) :: TH.Name -> TH.Name -> RewriteH Core)
                [ "Under construction "
                ] .+ Introduce .+ Context .+ Experiment .+ PreCondition
         ]

fixLocation :: String
fixLocation = "Data.Function.fix"

fixIdT :: TranslateH a Id
fixIdT = contextonlyT $ \ c -> findId c fixLocation

guardIsFixId :: Id -> TranslateH a ()
guardIsFixId v = do fixId <- fixIdT
                    guardMsg (v == fixId) (var2String v ++ " does not match " ++ fixLocation)


-- |  f = e   ==>   f = fix (\ f -> e)
fixIntro :: RewriteH CoreDef
fixIntro = prefixFailMsg "Fix introduction failed: " $
           do Def f e <- idR
              fixId   <- fixIdT
              constT $ do f' <- cloneIdH id f
                          let coreFix = App (App (Var fixId) (Type (idType f)))
                              emptySub = mkEmptySubst (mkInScopeSet (exprFreeVars e))
                              sub      = extendSubst emptySub f (Var f')
                          return $ Def f (coreFix (Lam f' (substExpr (text "fixIntro") sub e)))

-- ironically, this is an instance of worker/wrapper itself.

fixSpecialization :: RewriteH CoreExpr
fixSpecialization = do

        -- fix (t::*) (f :: t -> t) (a :: t) :: t
        App (App (App (Var fixId) (Type _)) _) _ <- idR -- TODO: couldn't that Type be a Var?  Might be better to use my "isType" fucntion.

        guardIsFixId fixId -- guardMsg (fx == fixId) "fixSpecialization only works on fix"

        let rr :: RewriteH CoreExpr
            rr = multiEtaExpand [TH.mkName "f",TH.mkName "a"]

            sub :: RewriteH Core
            sub = pathR [0,1] (promoteR rr)
        -- be careful this does not loop (it should not)
        extractR sub >>> fixSpecialization'


fixSpecialization' :: RewriteH CoreExpr
fixSpecialization' = do
        -- In normal form now
        App (App (App (Var fx) (Type t))
                 (Lam _ (Lam v2 (App (App e _) _a2)))
            )
            a <- idR

        t' <- case typeExprToType a of
                Just t2           -> return (applyTy t t2)
                Nothing           -> fail "Not a type variable." -- TODO: I've added this error message to avoid compiler-time warnings about missing cases, but this may have changed the semantics.  Generally I think this entire functions needs revisiting and cleaning up.  What's going on with all the dead-code (which I've commented out now).
--                   Var  a2  -> mkAppTy t (exprType t2)
--                   mkAppTy t t'


        -- TODO: t2' isn't used anywhere -- which means that a2 is never used ???
--        let t2' = case a2 of
--                   Type t2  -> applyTy t t2
--                   Var  a2  -> mkAppTy t (exprType t2)
--                   mkAppTy t t'


        v3 <- constT $ newVarH "f" t' -- (funArgTy t')
        v4 <- constT $ newTypeVarH "a" (tyVarKind v2)

         -- f' :: \/ a -> T [a] -> (\/ b . T [b])
        let f' = Lam v4  (Cast (Var v3)
                               (mkUnsafeCo t' (applyTy t (mkTyVarTy v4))))
        let e' = Lam v3 (App (App e f') a)

        return $ App (App (Var fx) (Type t')) e'


-- introSpecialisedPolyFun :: TH.Name -> TH.Name -> RewriteH CoreExpr
-- introSpecialisedPolyFun funNm ty = do funId <- lookupMatchingVarT funNm
--                                       tyVar <- lookupMatchingVarT ty



workerWrapperFacTest :: TH.Name -> TH.Name -> RewriteH CoreExpr
workerWrapperFacTest wrapNm unwrapNm = do wrapId   <- lookupMatchingVarT wrapNm
                                          unwrapId <- lookupMatchingVarT unwrapNm
                                          monomorphicWorkerWrapperFac (Var wrapId) (Var unwrapId)

workerWrapperSplitTest :: TH.Name -> TH.Name -> RewriteH CoreDef
workerWrapperSplitTest wrapNm unwrapNm = do wrapId   <- lookupMatchingVarT wrapNm
                                            unwrapId <- lookupMatchingVarT unwrapNm
                                            monomorphicWorkerWrapperSplit (Var wrapId) (Var unwrapId)


-- monomorphicWorkerWrapperFac :: Id -> Id -> RewriteH CoreExpr
-- monomorphicWorkerWrapperFac wrapId unwrapId = -- let wrapTy   = idType wrapId
--                                               --     unwrapTy = idType unwrapId
--                                               --     (wrapForallTyVars, wrapMainTy)     = splitForAllTys wrapTy
--                                               --     (unwrapForallTyVars, unwrapMainTy) = splitForAllTys unwrapTy

--                                               -- in  -- In progress: above are not used yet.
--                                                   workerWrapperFac (Var wrapId) (Var unwrapId)
--                                                 -- workerWrapperFac (mkTyApps (Var wrapId)   wrapForallTys)
--                                                 --                  (mkTyApps (Var unwrapId) unwrapForallTys)

-- workerWrapperFac (Var wrapId) (Var unwrapId)
-- splitForAllTys :: Type -> ([TyVar], Type)

-- monomorphicWorkerWrapperSplit :: Id -> Id -> RewriteH CoreDef
-- monomorphicWorkerWrapperSplit wrapId unwrapId = workerWrapperSplit (Var wrapId) (Var unwrapId)

-- substTyWith :: [TyVar] -> [Type] -> Type -> Type
-- mkTyApps  :: Expr b -> [Type]   -> Expr b

-- I assume there are GHC functions to do this, but I can't find them.
-- in progress
-- unifyTyVars :: [TyVar] -- | forall quantified type variables
--             -> Type    -- | type containing forall quantified type variables
--             -> Type    -- | type to unify with
--             -> Maybe [Type]  -- | types that the variables have been unified with
-- unifyTyVars vs tyGen tySpec = let unifyTyVarsAux tyGen tySpec vs
--                                in undefined
--   unifyTyVarsAux :: Type -> Type -> [(TyVar,[Type])] -> Maybe [(TyVar,[Type])]
--   unifyTyVarsAux (TyVarTy v)   t             = match v t
--   unifyTyVarsAux (AppTy s1 s2) (AppTy t1 t2) = match s1 t1 . match s2 t2


-- f      :: a -> a
-- wrap   :: forall x,y..z. b -> a
-- unwrap :: forall p,q..r. a -> b
-- fix tyA f ==> wrap (fix tyB (\ x -> unwrap (f (wrap (Var x)))))
-- Assumes the arguments are monomorphic functions (all type variables have alread been applied)
monomorphicWorkerWrapperFac :: CoreExpr -> CoreExpr -> RewriteH CoreExpr
monomorphicWorkerWrapperFac wrapE unwrapE =
  prefixFailMsg "Worker/wrapper Factorisation failed: " $
  withPatFailMsg (wrongExprForm "fix type fun") $
  do App (App (Var fixId) fixTyE) f <- idR  -- fix :: forall a. (a -> a) -> a
     guardIsFixId fixId
     case typeExprToType fixTyE of
       Nothing  -> fail "first argument to fix is not a type, this shouldn't have happened."
       Just tyA -> case splitFunTy_maybe (exprType wrapE) of
           Nothing                -> fail "type of wrapper is not a function."
           Just (tyB,wrapTyA) -> case splitFunTy_maybe (exprType unwrapE) of
             Nothing                    -> fail "type of unwrapper is not a function."
             Just (unwrapTyA,unwrapTyB) -> do guardMsg (eqType wrapTyA unwrapTyA) ("argument type of unwrapper does not match result type of wrapper.")
                                              guardMsg (eqType unwrapTyB tyB) ("argument type of wrapper does not match result type of unwrapper.")
                                              guardMsg (eqType wrapTyA tyA) ("wrapper/unwrapper types do not match expression type.")
                                              x <- constT (newVarH "x" tyB)
                                              return $ App wrapE
                                                           (App (App (Var fixId) (Type tyB))
                                                                (Lam x (App unwrapE
                                                                            (App f
                                                                                 (App wrapE
                                                                                      (Var x)
                                                                                 )
                                                                            )
                                                                       )
                                                                )
                                                           )


monomorphicWorkerWrapperSplit :: CoreExpr -> CoreExpr -> RewriteH CoreDef
monomorphicWorkerWrapperSplit wrap unwrap =
  let f    = TH.mkName "f"
      w    = TH.mkName "w"
      work = TH.mkName "work"
      fx   = TH.mkName "fix"
   in
      fixIntro >>> defR ( appAllR idR (letIntro f)
                            >>> letFloatArg
                            >>> letAllR idR ( monomorphicWorkerWrapperFac wrap unwrap
                                                >>> appAllR idR (letIntro w)
                                                >>> letFloatArg
                                                >>> letNonRecAllR (unfold fx >>> alphaLetOne (Just work) >>> extractR simplifyR) idR
                                                >>> letSubstR
                                                >>> letFloatArg
                                            )
                        )