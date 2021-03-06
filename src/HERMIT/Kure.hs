{-# LANGUAGE CPP, LambdaCase, FlexibleInstances, MultiParamTypeClasses, FlexibleContexts, UndecidableInstances, ScopedTypeVariables, InstanceSigs #-}

module HERMIT.Kure
       (
       -- * KURE

       -- | All the required functionality of KURE is exported here, so other modules do not need to import KURE directly.
         module Language.KURE
       , module Language.KURE.BiTranslate
       , module Language.KURE.Lens
       , module Language.KURE.ExtendableContext
       , module Language.KURE.Pathfinder
       -- * Sub-Modules
       , module HERMIT.Kure.SumTypes
       -- * Synonyms
       , TranslateH
       , RewriteH
       , BiRewriteH
       , LensH
       , PathH

       -- * Congruence combinators
       -- ** Modguts
       , modGutsT, modGutsR
       -- ** Program
       , progNilT
       , progConsT, progConsAllR, progConsAnyR, progConsOneR
       -- ** Binding Groups
       , nonRecT, nonRecAllR, nonRecAnyR, nonRecOneR
       , recT, recAllR, recAnyR, recOneR
       -- ** Recursive Definitions
       , defT, defAllR, defAnyR, defOneR
       -- ** Case Alternatives
       , altT, altAllR, altAnyR, altOneR
       -- ** Expressions
       , varT, varR
       , litT, litR
       , appT, appAllR, appAnyR, appOneR
       , lamT, lamAllR, lamAnyR, lamOneR
       , letT, letAllR, letAnyR, letOneR
       , caseT, caseAllR, caseAnyR, caseOneR
       , castT, castAllR, castAnyR, castOneR
       , tickT, tickAllR, tickAnyR, tickOneR
       , typeT, typeR
       , coercionT, coercionR
       -- ** Composite Congruence Combinators
       , defOrNonRecT, defOrNonRecAllR, defOrNonRecAnyR, defOrNonRecOneR
       , recDefT, recDefAllR, recDefAnyR, recDefOneR
       , letNonRecT, letNonRecAllR, letNonRecAnyR, letNonRecOneR
       , letRecT, letRecAllR, letRecAnyR, letRecOneR
       , letRecDefT, letRecDefAllR, letRecDefAnyR, letRecDefOneR
       , consNonRecT, consNonRecAllR, consNonRecAnyR, consNonRecOneR
       , consRecT, consRecAllR, consRecAnyR, consRecOneR
       , consRecDefT, consRecDefAllR, consRecDefAnyR, consRecDefOneR
       , caseAltT, caseAltAllR, caseAltAnyR, caseAltOneR
       -- ** Types
       , tyVarT, tyVarR
       , litTyT, litTyR
       , appTyT, appTyAllR, appTyAnyR, appTyOneR
       , funTyT, funTyAllR, funTyAnyR, funTyOneR
       , forAllTyT, forAllTyAllR, forAllTyAnyR, forAllTyOneR
       , tyConAppT, tyConAppAllR, tyConAppAnyR, tyConAppOneR
       -- ** Coercions
       , reflT, reflR
       , tyConAppCoT, tyConAppCoAllR, tyConAppCoAnyR, tyConAppCoOneR
       , appCoT, appCoAllR, appCoAnyR, appCoOneR
       , forAllCoT, forAllCoAllR, forAllCoAnyR, forAllCoOneR
       , coVarCoT, coVarCoR
       , axiomInstCoT, axiomInstCoAllR, axiomInstCoAnyR, axiomInstCoOneR
#if __GLASGOW_HASKELL__ > 706
#else
       , unsafeCoT, unsafeCoAllR, unsafeCoAnyR, unsafeCoOneR
#endif
       , symCoT, symCoR
       , transCoT, transCoAllR, transCoAnyR, transCoOneR
       , nthCoT, nthCoAllR, nthCoAnyR, nthCoOneR
       , instCoT, instCoAllR, instCoAnyR, instCoOneR
#if __GLASGOW_HASKELL__ > 706
       , lrCoT, lrCoAllR, lrCoAnyR, lrCoOneR
#else
#endif
       -- * Conversion to deprecated Int representation
       , deprecatedIntToCrumbT
       , deprecatedIntToPathT
       )
where

import Language.KURE
import Language.KURE.BiTranslate
import Language.KURE.Lens
import Language.KURE.ExtendableContext
import Language.KURE.Pathfinder

import HERMIT.Context
import HERMIT.Core
import HERMIT.GHC
import HERMIT.Monad
import HERMIT.Kure.SumTypes

import Control.Monad

import Data.Monoid (mempty)

---------------------------------------------------------------------

type TranslateH a b = Translate HermitC HermitM a b
type RewriteH a     = Rewrite   HermitC HermitM a
type BiRewriteH a   = BiRewrite HermitC HermitM a
type LensH a b      = Lens      HermitC HermitM a b
type PathH          = Path Crumb

-- I find it annoying that Applicative is not a superclass of Monad.
(<$>) :: Monad m => (a -> b) -> m a -> m b
(<$>) = liftM
{-# INLINE (<$>) #-}

(<*>) :: Monad m => m (a -> b) -> m a -> m b
(<*>) = ap
{-# INLINE (<*>) #-}

---------------------------------------------------------------------

-- | Walking over modules, programs, binding groups, definitions, expressions and case alternatives.
instance (ExtendPath c Crumb, AddBindings c) => Walker c Core where

  allR :: forall m. MonadCatch m => Rewrite c m Core -> Rewrite c m Core
  allR r = prefixFailMsg "allR failed: " $
           rewrite $ \ c -> \case
             GutsCore guts  -> inject <$> apply allRmodguts c guts
             ProgCore p     -> inject <$> apply allRprog c p
             BindCore bn    -> inject <$> apply allRbind c bn
             DefCore def    -> inject <$> apply allRdef c def
             AltCore alt    -> inject <$> apply allRalt c alt
             ExprCore e     -> inject <$> apply allRexpr c e
    where
      allRmodguts :: MonadCatch m => Rewrite c m ModGuts
      allRmodguts = modGutsR (extractR r)
      {-# INLINE allRmodguts #-}

      allRprog :: MonadCatch m => Rewrite c m CoreProg
      allRprog = readerT $ \case
                              ProgCons{}  -> progConsAllR (extractR r) (extractR r)
                              _           -> idR
      {-# INLINE allRprog #-}

      allRbind :: MonadCatch m => Rewrite c m CoreBind
      allRbind = readerT $ \case
                              NonRec{}  -> nonRecAllR idR (extractR r) -- we don't descend into the Var
                              Rec _     -> recAllR (const $ extractR r)
      {-# INLINE allRbind #-}

      allRdef :: MonadCatch m => Rewrite c m CoreDef
      allRdef = defAllR idR (extractR r) -- we don't descend into the Id
      {-# INLINE allRdef #-}

      allRalt :: MonadCatch m => Rewrite c m CoreAlt
      allRalt = altAllR idR (const idR) (extractR r) -- we don't descend into the AltCon or Vars
      {-# INLINE allRalt #-}

      allRexpr :: MonadCatch m => Rewrite c m CoreExpr
      allRexpr = readerT $ \case
                              App{}   -> appAllR (extractR r) (extractR r)
                              Lam{}   -> lamAllR idR (extractR r) -- we don't descend into the Var
                              Let{}   -> letAllR (extractR r) (extractR r)
                              Case{}  -> caseAllR (extractR r) idR idR (const $ extractR r) -- we don't descend into the case binder or Type
                              Cast{}  -> castAllR (extractR r) idR -- we don't descend into the Coercion
                              Tick{}  -> tickAllR idR (extractR r) -- we don't descend into the Tickish
                              _       -> idR
      {-# INLINE allRexpr #-}

-- NOTE: I tried telling GHC to inline allR and compilation hit the (default) simplifier tick limit.
-- TODO: Investigate whether that was achieving useful optimisations.

---------------------------------------------------------------------

-- | Walking over types (only).
instance (ExtendPath c Crumb, AddBindings c) => Walker c Type where

  allR :: MonadCatch m => Rewrite c m Type -> Rewrite c m Type
  allR r = prefixFailMsg "allR failed: " $
           readerT $ \case
                        AppTy{}     -> appTyAllR r r
                        FunTy{}     -> funTyAllR r r
                        ForAllTy{}  -> forAllTyAllR idR r
                        TyConApp{}  -> tyConAppAllR idR (const r)
                        _           -> idR

---------------------------------------------------------------------

-- | Walking over coercions (only).
instance (ExtendPath c Crumb, AddBindings c) => Walker c Coercion where

  allR :: MonadCatch m => Rewrite c m Coercion -> Rewrite c m Coercion
  allR r = prefixFailMsg "allR failed: " $
           readerT $ \case
                        TyConAppCo{}  -> tyConAppCoAllR idR (const r)
                        AppCo{}       -> appCoAllR r r
                        ForAllCo{}    -> forAllCoAllR idR r
                        SymCo{}       -> symCoR r
                        TransCo{}     -> transCoAllR r r
                        NthCo{}       -> nthCoAllR idR r
                        InstCo{}      -> instCoAllR r idR
#if __GLASGOW_HASKELL__ > 706
                        LRCo{}        -> lrCoAllR idR r
                        AxiomInstCo{} -> axiomInstCoAllR idR idR (const r)
#else
                        AxiomInstCo{} -> axiomInstCoAllR idR (const r)
#endif
                        _             -> idR

---------------------------------------------------------------------

-- | Walking over types and coercions.
instance (ExtendPath c Crumb, AddBindings c) => Walker c TyCo where

  allR :: forall m. MonadCatch m => Rewrite c m TyCo -> Rewrite c m TyCo
  allR r = prefixFailMsg "allR failed: " $
           rewrite $ \ c -> \case
             TypeCore ty     -> inject <$> apply (allR $ extractR r) c ty -- exploiting the fact that types do not contain coercions
             CoercionCore co -> inject <$> apply allRcoercion c co
    where
      allRcoercion :: MonadCatch m => Rewrite c m Coercion
      allRcoercion = readerT $ \case
                              Refl{}        -> reflR (extractR r)
                              TyConAppCo{}  -> tyConAppCoAllR idR (const $ extractR r) -- we don't descend into the TyCon
                              AppCo{}       -> appCoAllR (extractR r) (extractR r)
                              ForAllCo{}    -> forAllCoAllR idR (extractR r) -- we don't descend into the TyVar
#if __GLASGOW_HASKELL__ > 706
#else
                              UnsafeCo{}    -> unsafeCoAllR (extractR r) (extractR r)
#endif
                              SymCo{}       -> symCoR (extractR r)
                              TransCo{}     -> transCoAllR (extractR r) (extractR r)
                              InstCo{}      -> instCoAllR (extractR r) (extractR r)
                              NthCo{}       -> nthCoAllR idR (extractR r) -- we don't descend into the Int
#if __GLASGOW_HASKELL__ > 706
                              LRCo{}        -> lrCoAllR idR (extractR r)
                              AxiomInstCo{} -> axiomInstCoAllR idR idR (const $ extractR r) -- we don't descend into the axiom or index
#else
                              AxiomInstCo{} -> axiomInstCoAllR idR (const $ extractR r) -- we don't descend into the axiom
#endif
                              _             -> idR
      {-# INLINE allRcoercion #-}

---------------------------------------------------------------------

-- | Walking over modules, programs, binding groups, definitions, expressions and case alternatives.
instance (ExtendPath c Crumb, AddBindings c) => Walker c CoreTC where

  allR :: forall m. MonadCatch m => Rewrite c m CoreTC -> Rewrite c m CoreTC
  allR r = prefixFailMsg "allR failed: " $
           rewrite $ \ c -> \case
             Core (GutsCore guts)  -> inject <$> apply allRmodguts c guts
             Core (ProgCore p)     -> inject <$> apply allRprog c p
             Core (BindCore bn)    -> inject <$> apply allRbind c bn
             Core (DefCore def)    -> inject <$> apply allRdef c def
             Core (AltCore alt)    -> inject <$> apply allRalt c alt
             Core (ExprCore e)     -> inject <$> apply allRexpr c e
             TyCo tyCo             -> inject <$> apply (allR $ extractR r) c tyCo -- exploiting the fact that only types and coercions appear within types and coercions
    where
      allRmodguts :: MonadCatch m => Rewrite c m ModGuts
      allRmodguts = modGutsR (extractR r)
      {-# INLINE allRmodguts #-}

      allRprog :: MonadCatch m => Rewrite c m CoreProg
      allRprog = readerT $ \case
                              ProgCons{}  -> progConsAllR (extractR r) (extractR r)
                              _           -> idR
      {-# INLINE allRprog #-}

      allRbind :: MonadCatch m => Rewrite c m CoreBind
      allRbind = readerT $ \case
                              NonRec{}  -> nonRecAllR idR (extractR r) -- we don't descend into the Var
                              Rec _     -> recAllR (const $ extractR r)
      {-# INLINE allRbind #-}

      allRdef :: MonadCatch m => Rewrite c m CoreDef
      allRdef = defAllR idR (extractR r) -- we don't descend into the Id
      {-# INLINE allRdef #-}

      allRalt :: MonadCatch m => Rewrite c m CoreAlt
      allRalt = altAllR idR (const idR) (extractR r) -- we don't descend into the AltCon or Vars
      {-# INLINE allRalt #-}

      allRexpr :: MonadCatch m => Rewrite c m CoreExpr
      allRexpr = readerT $ \case
                              App{}      -> appAllR (extractR r) (extractR r)
                              Lam{}      -> lamAllR idR (extractR r) -- we don't descend into the Var
                              Let{}      -> letAllR (extractR r) (extractR r)
                              Case{}     -> caseAllR (extractR r) idR (extractR r) (const $ extractR r) -- we don't descend into the case binder
                              Cast{}     -> castAllR (extractR r) (extractR r)
                              Tick{}     -> tickAllR idR (extractR r) -- we don't descend into the Tickish
                              Type{}     -> typeR (extractR r)
                              Coercion{} -> coercionR (extractR r)
                              _          -> idR
      {-# INLINE allRexpr #-}

---------------------------------------------------------------------

-- | Translate a module.
--   Slightly different to the other congruence combinators: it passes in /all/ of the original to the reconstruction function.
modGutsT :: (ExtendPath c Crumb, Monad m) => Translate c m CoreProg a -> (ModGuts -> a -> b) -> Translate c m ModGuts b
modGutsT t f = translate $ \ c guts -> f guts <$> apply t (c @@ ModGuts_Prog) (bindsToProg $ mg_binds guts)
{-# INLINE modGutsT #-}

-- | Rewrite the 'CoreProg' child of a module.
modGutsR :: (ExtendPath c Crumb, Monad m) => Rewrite c m CoreProg -> Rewrite c m ModGuts
modGutsR r = modGutsT r (\ guts p -> guts {mg_binds = progToBinds p})
{-# INLINE modGutsR #-}

---------------------------------------------------------------------

-- | Translate an empty list.
progNilT :: Monad m => b -> Translate c m CoreProg b
progNilT b = contextfreeT $ \case
                               ProgNil       -> return b
                               ProgCons _ _  -> fail "not an empty program."
{-# INLINE progNilT #-}

-- | Translate a program of the form: ('CoreBind' @:@ 'CoreProg')
progConsT :: (ExtendPath c Crumb, AddBindings c, Monad m) => Translate c m CoreBind a1 -> Translate c m CoreProg a2 -> (a1 -> a2 -> b) -> Translate c m CoreProg b
progConsT t1 t2 f = translate $ \ c -> \case
                                          ProgCons bd p -> f <$> apply t1 (c @@ ProgCons_Head) bd <*> apply t2 (addBindingGroup bd c @@ ProgCons_Tail) p
                                          _             -> fail "not a non-empty program."
{-# INLINE progConsT #-}

-- | Rewrite all children of a program of the form: ('CoreBind' @:@ 'CoreProg')
progConsAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => Rewrite c m CoreBind -> Rewrite c m CoreProg -> Rewrite c m CoreProg
progConsAllR r1 r2 = progConsT r1 r2 ProgCons
{-# INLINE progConsAllR #-}

-- | Rewrite any children of a program of the form: ('CoreBind' @:@ 'CoreProg')
progConsAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m CoreBind -> Rewrite c m CoreProg -> Rewrite c m CoreProg
progConsAnyR r1 r2 = unwrapAnyR $ progConsAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE progConsAnyR #-}

-- | Rewrite one child of a program of the form: ('CoreBind' @:@ 'CoreProg')
progConsOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m CoreBind -> Rewrite c m CoreProg -> Rewrite c m CoreProg
progConsOneR r1 r2 = unwrapOneR $  progConsAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE progConsOneR #-}

---------------------------------------------------------------------

-- | Translate a binding group of the form: @NonRec@ 'Var' 'CoreExpr'
nonRecT :: (ExtendPath c Crumb, Monad m) => Translate c m Var a1 -> Translate c m CoreExpr a2 -> (a1 -> a2 -> b) -> Translate c m CoreBind b
nonRecT t1 t2 f = translate $ \ c -> \case
                                        NonRec v e -> f <$> apply t1 (c @@ NonRec_Var) v <*> apply t2 (c @@ NonRec_RHS) e
                                        _          -> fail "not a non-recursive binding group."
{-# INLINE nonRecT #-}

-- | Rewrite all children of a binding group of the form: @NonRec@ 'Var' 'CoreExpr'
nonRecAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreBind
nonRecAllR r1 r2 = nonRecT r1 r2 NonRec
{-# INLINE nonRecAllR #-}

-- | Rewrite any children of a binding group of the form: @NonRec@ 'Var' 'CoreExpr'
nonRecAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreBind
nonRecAnyR r1 r2 = unwrapAnyR (nonRecAllR (wrapAnyR r1) (wrapAnyR r2))
{-# INLINE nonRecAnyR #-}

-- | Rewrite one child of a binding group of the form: @NonRec@ 'Var' 'CoreExpr'
nonRecOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreBind
nonRecOneR r1 r2 = unwrapOneR (nonRecAllR (wrapOneR r1) (wrapOneR r2))
{-# INLINE nonRecOneR #-}


-- | Translate a binding group of the form: @Rec@ ['CoreDef']
recT :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> Translate c m CoreDef a) -> ([a] -> b) -> Translate c m CoreBind b
recT t f = translate $ \ c -> \case
         Rec bds -> -- The group is recursive, so we add all other bindings in the group to the context (excluding the one under consideration).
                    f <$> sequence [ apply (t n) (addDefBindingsExcept n bds c @@ Rec_Def n) (Def i e) -- here we convert from (Id,CoreExpr) to CoreDef
                                   | ((i,e),n) <- zip bds [0..]
                                   ]
         _       -> fail "not a recursive binding group."
{-# INLINE recT #-}

-- | Rewrite all children of a binding group of the form: @Rec@ ['CoreDef']
recAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> Rewrite c m CoreDef) -> Rewrite c m CoreBind
recAllR rs = recT rs defsToRecBind
{-# INLINE recAllR #-}

-- | Rewrite any children of a binding group of the form: @Rec@ ['CoreDef']
recAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> Rewrite c m CoreDef) -> Rewrite c m CoreBind
recAnyR rs = unwrapAnyR $ recAllR (wrapAnyR . rs)
{-# INLINE recAnyR #-}

-- | Rewrite one child of a binding group of the form: @Rec@ ['CoreDef']
recOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> Rewrite c m CoreDef) -> Rewrite c m CoreBind
recOneR rs = unwrapOneR $ recAllR (wrapOneR . rs)
{-# INLINE recOneR #-}

---------------------------------------------------------------------

-- | Translate a recursive definition of the form: @Def@ 'Id' 'CoreExpr'
defT :: (ExtendPath c Crumb, AddBindings c, Monad m) => Translate c m Id a1 -> Translate c m CoreExpr a2 -> (a1 -> a2 -> b) -> Translate c m CoreDef b
defT t1 t2 f = translate $ \ c (Def i e) -> f <$> apply t1 (c @@ Def_Id) i <*> apply t2 (addDefBinding i c @@ Def_RHS) e
{-# INLINE defT #-}

-- | Rewrite all children of a recursive definition of the form: @Def@ 'Id' 'CoreExpr'
defAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => Rewrite c m Id -> Rewrite c m CoreExpr -> Rewrite c m CoreDef
defAllR r1 r2 = defT r1 r2 Def
{-# INLINE defAllR #-}

-- | Rewrite any children of a recursive definition of the form: @Def@ 'Id' 'CoreExpr'
defAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Id -> Rewrite c m CoreExpr -> Rewrite c m CoreDef
defAnyR r1 r2 = unwrapAnyR (defAllR (wrapAnyR r1) (wrapAnyR r2))
{-# INLINE defAnyR #-}

-- | Rewrite one child of a recursive definition of the form: @Def@ 'Id' 'CoreExpr'
defOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Id -> Rewrite c m CoreExpr -> Rewrite c m CoreDef
defOneR r1 r2 = unwrapOneR (defAllR (wrapOneR r1) (wrapOneR r2))
{-# INLINE defOneR #-}

---------------------------------------------------------------------

-- | Translate a case alternative of the form: ('AltCon', ['Var'], 'CoreExpr')
altT :: (ExtendPath c Crumb, AddBindings c, Monad m) => Translate c m AltCon a1 -> (Int -> Translate c m Var a2) -> Translate c m CoreExpr a3 -> (a1 -> [a2] -> a3 -> b) -> Translate c m CoreAlt b
altT t1 ts t2 f = translate $ \ c (con,vs,e) -> f <$> apply t1 (c @@ Alt_Con) con
                                                  <*> sequence [ apply (ts n) (c @@ Alt_Var n) v | (v,n) <- zip vs [1..] ]
                                                  <*> apply t2 (addAltBindings vs c @@ Alt_RHS) e
{-# INLINE altT #-}

-- | Rewrite all children of a case alternative of the form: ('AltCon', 'Id', 'CoreExpr')
altAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => Rewrite c m AltCon -> (Int -> Rewrite c m Var) -> Rewrite c m CoreExpr -> Rewrite c m CoreAlt
altAllR r1 rs r2 = altT r1 rs r2 (,,)
{-# INLINE altAllR #-}

-- | Rewrite any children of a case alternative of the form: ('AltCon', 'Id', 'CoreExpr')
altAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m AltCon -> (Int -> Rewrite c m Var) -> Rewrite c m CoreExpr -> Rewrite c m CoreAlt
altAnyR r1 rs r2 = unwrapAnyR (altAllR (wrapAnyR r1) (wrapAnyR . rs) (wrapAnyR r2))
{-# INLINE altAnyR #-}

-- | Rewrite one child of a case alternative of the form: ('AltCon', 'Id', 'CoreExpr')
altOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m AltCon -> (Int -> Rewrite c m Var) -> Rewrite c m CoreExpr -> Rewrite c m CoreAlt
altOneR r1 rs r2 = unwrapOneR (altAllR (wrapOneR r1) (wrapOneR . rs) (wrapOneR r2))
{-# INLINE altOneR #-}

---------------------------------------------------------------------

-- | Translate an expression of the form: @Var@ 'Id'
varT :: (ExtendPath c Crumb, Monad m) => Translate c m Id b -> Translate c m CoreExpr b
varT t = translate $ \ c -> \case
                               Var v -> apply t (c @@ Var_Id) v
                               _     -> fail "not a variable."
{-# INLINE varT #-}

-- | Rewrite the 'Id' child in an expression of the form: @Var@ 'Id'
varR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Id -> Rewrite c m CoreExpr
varR r = varT (Var <$> r)
{-# INLINE varR #-}


-- | Translate an expression of the form: @Lit@ 'Literal'
litT :: (ExtendPath c Crumb, Monad m) => Translate c m Literal b -> Translate c m CoreExpr b
litT t = translate $ \ c -> \case
                               Lit x -> apply t (c @@ Lit_Lit) x
                               _     -> fail "not a literal."
{-# INLINE litT #-}

-- | Rewrite the 'Literal' child in an expression of the form: @Lit@ 'Literal'
litR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Literal -> Rewrite c m CoreExpr
litR r = litT (Lit <$> r)
{-# INLINE litR #-}


-- | Translate an expression of the form: @App@ 'CoreExpr' 'CoreExpr'
appT :: (ExtendPath c Crumb, Monad m) => Translate c m CoreExpr a1 -> Translate c m CoreExpr a2 -> (a1 -> a2 -> b) -> Translate c m CoreExpr b
appT t1 t2 f = translate $ \ c -> \case
                                     App e1 e2 -> f <$> apply t1 (c @@ App_Fun) e1 <*> apply t2 (c @@ App_Arg) e2
                                     _         -> fail "not an application."
{-# INLINE appT #-}

-- | Rewrite all children of an expression of the form: @App@ 'CoreExpr' 'CoreExpr'
appAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m CoreExpr -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
appAllR r1 r2 = appT r1 r2 App
{-# INLINE appAllR #-}

-- | Rewrite any children of an expression of the form: @App@ 'CoreExpr' 'CoreExpr'
appAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m CoreExpr -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
appAnyR r1 r2 = unwrapAnyR $ appAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE appAnyR #-}

-- | Rewrite one child of an expression of the form: @App@ 'CoreExpr' 'CoreExpr'
appOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m CoreExpr -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
appOneR r1 r2 = unwrapOneR $ appAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE appOneR #-}


-- | Translate an expression of the form: @Lam@ 'Var' 'CoreExpr'
lamT :: (ExtendPath c Crumb, AddBindings c, Monad m) => Translate c m Var a1 -> Translate c m CoreExpr a2 -> (a1 -> a2 -> b) -> Translate c m CoreExpr b
lamT t1 t2 f = translate $ \ c -> \case
                                     Lam v e -> f <$> apply t1 (c @@ Lam_Var) v <*> apply t2 (addLambdaBinding v c @@ Lam_Body) e
                                     _       -> fail "not a lambda."
{-# INLINE lamT #-}

-- | Rewrite all children of an expression of the form: @Lam@ 'Var' 'CoreExpr'
lamAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
lamAllR r1 r2 = lamT r1 r2 Lam
{-# INLINE lamAllR #-}

-- | Rewrite any children of an expression of the form: @Lam@ 'Var' 'CoreExpr'
lamAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
lamAnyR r1 r2 = unwrapAnyR $ lamAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE lamAnyR #-}

-- | Rewrite one child of an expression of the form: @Lam@ 'Var' 'CoreExpr'
lamOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
lamOneR r1 r2 = unwrapOneR $ lamAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE lamOneR #-}


-- | Translate an expression of the form: @Let@ 'CoreBind' 'CoreExpr'
letT :: (ExtendPath c Crumb, AddBindings c, Monad m) => Translate c m CoreBind a1 -> Translate c m CoreExpr a2 -> (a1 -> a2 -> b) -> Translate c m CoreExpr b
letT t1 t2 f = translate $ \ c -> \case
        Let bds e -> -- Note we use the *original* context for the binding group.
                     -- If the bindings are recursive, they will be added to the context by recT.
                     f <$> apply t1 (c @@ Let_Bind) bds <*> apply t2 (addBindingGroup bds c @@ Let_Body) e
        _         -> fail "not a let node."
{-# INLINE letT #-}

-- | Rewrite all children of an expression of the form: @Let@ 'CoreBind' 'CoreExpr'
letAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => Rewrite c m CoreBind -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letAllR r1 r2 = letT r1 r2 Let
{-# INLINE letAllR #-}

-- | Rewrite any children of an expression of the form: @Let@ 'CoreBind' 'CoreExpr'
letAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m CoreBind -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letAnyR r1 r2 = unwrapAnyR $ letAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE letAnyR #-}

-- | Rewrite one child of an expression of the form: @Let@ 'CoreBind' 'CoreExpr'
letOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m CoreBind -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letOneR r1 r2 = unwrapOneR $ letAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE letOneR #-}


-- | Translate an expression of the form: @Case@ 'CoreExpr' 'Id' 'Type' ['CoreAlt']
caseT :: (ExtendPath c Crumb, AddBindings c, Monad m)
      => Translate c m CoreExpr e
      -> Translate c m Id w
      -> Translate c m Type ty
      -> (Int -> Translate c m CoreAlt alt)
      -> (e -> w -> ty -> [alt] -> b)
      -> Translate c m CoreExpr b
caseT te tw tty talts f = translate $ \ c -> \case
         Case e w ty alts -> f <$> apply te (c @@ Case_Scrutinee) e
                               <*> apply tw (c @@ Case_Binder) w
                               <*> apply tty (c @@ Case_Type) ty
                               <*> sequence [ apply (talts n) (addCaseWildBinding (w,e,alt) c @@ Case_Alt n) alt
                                            | (alt,n) <- zip alts [0..]
                                            ]
         _                -> fail "not a case."
{-# INLINE caseT #-}

-- | Rewrite all children of an expression of the form: @Case@ 'CoreExpr' 'Id' 'Type' ['CoreAlt']
caseAllR :: (ExtendPath c Crumb, AddBindings c, Monad m)
         => Rewrite c m CoreExpr
         -> Rewrite c m Id
         -> Rewrite c m Type
         -> (Int -> Rewrite c m CoreAlt)
         -> Rewrite c m CoreExpr
caseAllR re rw rty ralts = caseT re rw rty ralts Case
{-# INLINE caseAllR #-}

-- | Rewrite any children of an expression of the form: @Case@ 'CoreExpr' 'Id' 'Type' ['CoreAlt']
caseAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m)
         => Rewrite c m CoreExpr
         -> Rewrite c m Id
         -> Rewrite c m Type
         -> (Int -> Rewrite c m CoreAlt)
         -> Rewrite c m CoreExpr
caseAnyR re rw rty ralts = unwrapAnyR $ caseAllR (wrapAnyR re) (wrapAnyR rw) (wrapAnyR rty) (wrapAnyR . ralts)
{-# INLINE caseAnyR #-}

-- | Rewrite one child of an expression of the form: @Case@ 'CoreExpr' 'Id' 'Type' ['CoreAlt']
caseOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m)
         => Rewrite c m CoreExpr
         -> Rewrite c m Id
         -> Rewrite c m Type
         -> (Int -> Rewrite c m CoreAlt)
         -> Rewrite c m CoreExpr
caseOneR re rw rty ralts = unwrapOneR $ caseAllR (wrapOneR re) (wrapOneR rw) (wrapOneR rty) (wrapOneR . ralts)
{-# INLINE caseOneR #-}


-- | Translate an expression of the form: @Cast@ 'CoreExpr' 'Coercion'
castT :: (ExtendPath c Crumb, Monad m) => Translate c m CoreExpr a1 -> Translate c m Coercion a2 -> (a1 -> a2 -> b) -> Translate c m CoreExpr b
castT t1 t2 f = translate $ \ c -> \case
                                      Cast e co -> f <$> apply t1 (c @@ Cast_Expr) e <*> apply t2 (c @@ Cast_Co) co
                                      _         -> fail "not a cast."
{-# INLINE castT #-}

-- | Rewrite all children of an expression of the form: @Cast@ 'CoreExpr' 'Coercion'
castAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m CoreExpr -> Rewrite c m Coercion -> Rewrite c m CoreExpr
castAllR r1 r2 = castT r1 r2 Cast
{-# INLINE castAllR #-}

-- | Rewrite any children of an expression of the form: @Cast@ 'CoreExpr' 'Coercion'
castAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m CoreExpr -> Rewrite c m Coercion -> Rewrite c m CoreExpr
castAnyR r1 r2 = unwrapAnyR $ castAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE castAnyR #-}

-- | Rewrite one child of an expression of the form: @Cast@ 'CoreExpr' 'Coercion'
castOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m CoreExpr -> Rewrite c m Coercion -> Rewrite c m CoreExpr
castOneR r1 r2 = unwrapOneR $ castAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE castOneR #-}


-- | Translate an expression of the form: @Tick@ 'CoreTickish' 'CoreExpr'
tickT :: (ExtendPath c Crumb, Monad m) => Translate c m CoreTickish a1 -> Translate c m CoreExpr a2 -> (a1 -> a2 -> b) -> Translate c m CoreExpr b
tickT t1 t2 f = translate $ \ c -> \case
                                      Tick tk e -> f <$> apply t1 (c @@ Tick_Tick) tk <*> apply t2 (c @@ Tick_Expr) e
                                      _         -> fail "not a tick."
{-# INLINE tickT #-}

-- | Rewrite all children of an expression of the form: @Tick@ 'CoreTickish' 'CoreExpr'
tickAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m CoreTickish -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
tickAllR r1 r2 = tickT r1 r2 Tick
{-# INLINE tickAllR #-}

-- | Rewrite any children of an expression of the form: @Tick@ 'CoreTickish' 'CoreExpr'
tickAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m CoreTickish -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
tickAnyR r1 r2 = unwrapAnyR $ tickAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE tickAnyR #-}

-- | Rewrite any children of an expression of the form: @Tick@ 'CoreTickish' 'CoreExpr'
tickOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m CoreTickish -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
tickOneR r1 r2 = unwrapOneR $ tickAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE tickOneR #-}


-- | Translate an expression of the form: @Type@ 'Type'
typeT :: (ExtendPath c Crumb, Monad m) => Translate c m Type b -> Translate c m CoreExpr b
typeT t = translate $ \ c -> \case
                                Type ty -> apply t (c @@ Type_Type) ty
                                _       -> fail "not a type."
{-# INLINE typeT #-}

-- | Rewrite the 'Type' child in an expression of the form: @Type@ 'Type'
typeR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Type -> Rewrite c m CoreExpr
typeR r = typeT (Type <$> r)
{-# INLINE typeR #-}


-- | Translate an expression of the form: @Coercion@ 'Coercion'
coercionT :: (ExtendPath c Crumb, Monad m) => Translate c m Coercion b -> Translate c m CoreExpr b
coercionT t = translate $ \ c -> \case
                                    Coercion co -> apply t (c @@ Co_Co) co
                                    _           -> fail "not a coercion."
{-# INLINE coercionT #-}

-- | Rewrite the 'Coercion' child in an expression of the form: @Coercion@ 'Coercion'
coercionR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Coercion -> Rewrite c m CoreExpr
coercionR r = coercionT (Coercion <$> r)
{-# INLINE coercionR #-}

---------------------------------------------------------------------

-- Some composite congruence combinators to export.

-- | Translate a definition of the form @NonRec 'Var' 'CoreExpr'@ or @Def 'Id' 'CoreExpr'@
defOrNonRecT :: (Injection CoreBind g, Injection CoreDef g, ExtendPath c Crumb, AddBindings c, MonadCatch m) => Translate c m Var a1 -> Translate c m CoreExpr a2 -> (a1 -> a2 -> b) -> Translate c m g b
defOrNonRecT t1 t2 f = promoteBindT (nonRecT t1 t2 f)
                    <+ promoteDefT  (defT    t1 t2 f)
{-# INLINE defOrNonRecT #-}

-- | Rewrite all children of a definition of the form @NonRec 'Var' 'CoreExpr'@ or @Def 'Id' 'CoreExpr'@
defOrNonRecAllR :: (Injection CoreBind g, Injection CoreDef g, ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m g
defOrNonRecAllR r1 r2 = promoteBindR (nonRecAllR r1 r2)
                     <+ promoteDefR  (defAllR    r1 r2)
{-# INLINE defOrNonRecAllR #-}

-- | Rewrite any children of a definition of the form @NonRec 'Var' 'CoreExpr'@ or @Def 'Id' 'CoreExpr'@
defOrNonRecAnyR :: (Injection CoreBind g, Injection CoreDef g, ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m g
defOrNonRecAnyR r1 r2 = unwrapAnyR $ defOrNonRecAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE defOrNonRecAnyR #-}

-- | Rewrite one child of a definition of the form @NonRec 'Var' 'CoreExpr'@ or @Def 'Id' 'CoreExpr'@
defOrNonRecOneR :: (Injection CoreBind g, Injection CoreDef g, ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m g
defOrNonRecOneR r1 r2 = unwrapAnyR $ defOrNonRecOneR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE defOrNonRecOneR #-}


-- | Translate a binding group of the form: @Rec@ [('Id', 'CoreExpr')]
recDefT :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> (Translate c m Id a1, Translate c m CoreExpr a2)) -> ([(a1,a2)] -> b) -> Translate c m CoreBind b
recDefT ts = recT (\ n -> uncurry defT (ts n) (,))
{-# INLINE recDefT #-}

-- | Rewrite all children of a binding group of the form: @Rec@ [('Id', 'CoreExpr')]
recDefAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> (Rewrite c m Id, Rewrite c m CoreExpr)) -> Rewrite c m CoreBind
recDefAllR rs = recAllR (\ n -> uncurry defAllR (rs n))
{-# INLINE recDefAllR #-}

-- | Rewrite any children of a binding group of the form: @Rec@ [('Id', 'CoreExpr')]
recDefAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> (Rewrite c m Id, Rewrite c m CoreExpr)) -> Rewrite c m CoreBind
recDefAnyR rs = recAnyR (\ n -> uncurry defAnyR (rs n))
{-# INLINE recDefAnyR #-}

-- | Rewrite one child of a binding group of the form: @Rec@ [('Id', 'CoreExpr')]
recDefOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> (Rewrite c m Id, Rewrite c m CoreExpr)) -> Rewrite c m CoreBind
recDefOneR rs = recOneR (\ n -> uncurry defOneR (rs n))
{-# INLINE recDefOneR #-}


-- | Translate a program of the form: (@NonRec@ 'Var' 'CoreExpr') @:@ 'CoreProg'
consNonRecT :: (ExtendPath c Crumb, AddBindings c, Monad m) => Translate c m Var a1 -> Translate c m CoreExpr a2 -> Translate c m CoreProg a3 -> (a1 -> a2 -> a3 -> b) -> Translate c m CoreProg b
consNonRecT t1 t2 t3 f = progConsT (nonRecT t1 t2 (,)) t3 (uncurry f)
{-# INLINE consNonRecT #-}

-- | Rewrite all children of an expression of the form: (@NonRec@ 'Var' 'CoreExpr') @:@ 'CoreProg'
consNonRecAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreProg -> Rewrite c m CoreProg
consNonRecAllR r1 r2 r3 = progConsAllR (nonRecAllR r1 r2) r3
{-# INLINE consNonRecAllR #-}

-- | Rewrite any children of an expression of the form: (@NonRec@ 'Var' 'CoreExpr') @:@ 'CoreProg'
consNonRecAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreProg -> Rewrite c m CoreProg
consNonRecAnyR r1 r2 r3 = progConsAllR (nonRecAnyR r1 r2) r3
{-# INLINE consNonRecAnyR #-}

-- | Rewrite one child of an expression of the form: (@NonRec@ 'Var' 'CoreExpr') @:@ 'CoreProg'
consNonRecOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreProg -> Rewrite c m CoreProg
consNonRecOneR r1 r2 r3 = progConsAllR (nonRecOneR r1 r2) r3
{-# INLINE consNonRecOneR #-}


-- | Translate an expression of the form: (@Rec@ ['CoreDef']) @:@ 'CoreProg'
consRecT :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> Translate c m CoreDef a1) -> Translate c m CoreProg a2 -> ([a1] -> a2 -> b) -> Translate c m CoreProg b
consRecT ts t = progConsT (recT ts id) t
{-# INLINE consRecT #-}

-- | Rewrite all children of an expression of the form: (@Rec@ ['CoreDef']) @:@ 'CoreProg'
consRecAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> Rewrite c m CoreDef) -> Rewrite c m CoreProg -> Rewrite c m CoreProg
consRecAllR rs r = progConsAllR (recAllR rs) r
{-# INLINE consRecAllR #-}

-- | Rewrite any children of an expression of the form: (@Rec@ ['CoreDef']) @:@ 'CoreProg'
consRecAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> Rewrite c m CoreDef) -> Rewrite c m CoreProg -> Rewrite c m CoreProg
consRecAnyR rs r = progConsAnyR (recAnyR rs) r
{-# INLINE consRecAnyR #-}

-- | Rewrite one child of an expression of the form: (@Rec@ ['CoreDef']) @:@ 'CoreProg'
consRecOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> Rewrite c m CoreDef) -> Rewrite c m CoreProg -> Rewrite c m CoreProg
consRecOneR rs r = progConsOneR (recOneR rs) r
{-# INLINE consRecOneR #-}


-- | Translate an expression of the form: (@Rec@ [('Id', 'CoreExpr')]) @:@ 'CoreProg'
consRecDefT :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> (Translate c m Id a1, Translate c m CoreExpr a2)) -> Translate c m CoreProg a3 -> ([(a1,a2)] -> a3 -> b) -> Translate c m CoreProg b
consRecDefT ts t = consRecT (\ n -> uncurry defT (ts n) (,)) t
{-# INLINE consRecDefT #-}

-- | Rewrite all children of an expression of the form: (@Rec@ [('Id', 'CoreExpr')]) @:@ 'CoreProg'
consRecDefAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> (Rewrite c m Id, Rewrite c m CoreExpr)) -> Rewrite c m CoreProg -> Rewrite c m CoreProg
consRecDefAllR rs r = consRecAllR (\ n -> uncurry defAllR (rs n)) r
{-# INLINE consRecDefAllR #-}

-- | Rewrite any children of an expression of the form: (@Rec@ [('Id', 'CoreExpr')]) @:@ 'CoreProg'
consRecDefAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> (Rewrite c m Id, Rewrite c m CoreExpr)) -> Rewrite c m CoreProg -> Rewrite c m CoreProg
consRecDefAnyR rs r = consRecAnyR (\ n -> uncurry defAnyR (rs n)) r
{-# INLINE consRecDefAnyR #-}

-- | Rewrite one child of an expression of the form: (@Rec@ [('Id', 'CoreExpr')]) @:@ 'CoreProg'
consRecDefOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> (Rewrite c m Id, Rewrite c m CoreExpr)) -> Rewrite c m CoreProg -> Rewrite c m CoreProg
consRecDefOneR rs r = consRecOneR (\ n -> uncurry defOneR (rs n)) r
{-# INLINE consRecDefOneR #-}


-- | Translate an expression of the form: @Let@ (@NonRec@ 'Var' 'CoreExpr') 'CoreExpr'
letNonRecT :: (ExtendPath c Crumb, AddBindings c, Monad m) => Translate c m Var a1 -> Translate c m CoreExpr a2 -> Translate c m CoreExpr a3 -> (a1 -> a2 -> a3 -> b) -> Translate c m CoreExpr b
letNonRecT t1 t2 t3 f = letT (nonRecT t1 t2 (,)) t3 (uncurry f)
{-# INLINE letNonRecT #-}

-- | Rewrite all children of an expression of the form: @Let@ (@NonRec@ 'Var' 'CoreExpr') 'CoreExpr'
letNonRecAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letNonRecAllR r1 r2 r3 = letAllR (nonRecAllR r1 r2) r3
{-# INLINE letNonRecAllR #-}

-- | Rewrite any children of an expression of the form: @Let@ (@NonRec@ 'Var' 'CoreExpr') 'CoreExpr'
letNonRecAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letNonRecAnyR r1 r2 r3 = letAnyR (nonRecAnyR r1 r2) r3
{-# INLINE letNonRecAnyR #-}

-- | Rewrite one child of an expression of the form: @Let@ (@NonRec@ 'Var' 'CoreExpr') 'CoreExpr'
letNonRecOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letNonRecOneR r1 r2 r3 = letOneR (nonRecOneR r1 r2) r3
{-# INLINE letNonRecOneR #-}


-- | Translate an expression of the form: @Let@ (@Rec@ ['CoreDef']) 'CoreExpr'
letRecT :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> Translate c m CoreDef a1) -> Translate c m CoreExpr a2 -> ([a1] -> a2 -> b) -> Translate c m CoreExpr b
letRecT ts t = letT (recT ts id) t
{-# INLINE letRecT #-}

-- | Rewrite all children of an expression of the form: @Let@ (@Rec@ ['CoreDef']) 'CoreExpr'
letRecAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> Rewrite c m CoreDef) -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letRecAllR rs r = letAllR (recAllR rs) r
{-# INLINE letRecAllR #-}

-- | Rewrite any children of an expression of the form: @Let@ (@Rec@ ['CoreDef']) 'CoreExpr'
letRecAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> Rewrite c m CoreDef) -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letRecAnyR rs r = letAnyR (recAnyR rs) r
{-# INLINE letRecAnyR #-}

-- | Rewrite one child of an expression of the form: @Let@ (@Rec@ ['CoreDef']) 'CoreExpr'
letRecOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> Rewrite c m CoreDef) -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letRecOneR rs r = letOneR (recOneR rs) r
{-# INLINE letRecOneR #-}


-- | Translate an expression of the form: @Let@ (@Rec@ [('Id', 'CoreExpr')]) 'CoreExpr'
letRecDefT :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> (Translate c m Id a1, Translate c m CoreExpr a2)) -> Translate c m CoreExpr a3 -> ([(a1,a2)] -> a3 -> b) -> Translate c m CoreExpr b
letRecDefT ts t = letRecT (\ n -> uncurry defT (ts n) (,)) t
{-# INLINE letRecDefT #-}

-- | Rewrite all children of an expression of the form: @Let@ (@Rec@ [('Id', 'CoreExpr')]) 'CoreExpr'
letRecDefAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> (Rewrite c m Id, Rewrite c m CoreExpr)) -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letRecDefAllR rs r = letRecAllR (\ n -> uncurry defAllR (rs n)) r
{-# INLINE letRecDefAllR #-}

-- | Rewrite any children of an expression of the form: @Let@ (@Rec@ [('Id', 'CoreExpr')]) 'CoreExpr'
letRecDefAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> (Rewrite c m Id, Rewrite c m CoreExpr)) -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letRecDefAnyR rs r = letRecAnyR (\ n -> uncurry defAnyR (rs n)) r
{-# INLINE letRecDefAnyR #-}

-- | Rewrite one child of an expression of the form: @Let@ (@Rec@ [('Id', 'CoreExpr')]) 'CoreExpr'
letRecDefOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> (Rewrite c m Id, Rewrite c m CoreExpr)) -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letRecDefOneR rs r = letRecOneR (\ n -> uncurry defOneR (rs n)) r
{-# INLINE letRecDefOneR #-}


-- | Translate an expression of the form: @Case@ 'CoreExpr' 'Id' 'Type' [('AltCon', ['Var'], 'CoreExpr')]
caseAltT :: (ExtendPath c Crumb, AddBindings c, Monad m)
         => Translate c m CoreExpr sc
         -> Translate c m Id w
         -> Translate c m Type ty
         -> (Int -> (Translate c m AltCon con, (Int -> Translate c m Var v), Translate c m CoreExpr rhs)) -> (sc -> w -> ty -> [(con,[v],rhs)] -> b)
         -> Translate c m CoreExpr b
caseAltT tsc tw tty talts = caseT tsc tw tty (\ n -> let (tcon,tvs,te) = talts n in altT tcon tvs te (,,))
{-# INLINE caseAltT #-}

-- | Rewrite all children of an expression of the form: @Case@ 'CoreExpr' 'Id' 'Type' [('AltCon', ['Var'], 'CoreExpr')]
caseAltAllR :: (ExtendPath c Crumb, AddBindings c, Monad m)
            => Rewrite c m CoreExpr
            -> Rewrite c m Id
            -> Rewrite c m Type
            -> (Int -> (Rewrite c m AltCon, (Int -> Rewrite c m Var), Rewrite c m CoreExpr))
            -> Rewrite c m CoreExpr
caseAltAllR rsc rw rty ralts = caseAllR rsc rw rty (\ n -> let (rcon,rvs,re) = ralts n in altAllR rcon rvs re)
{-# INLINE caseAltAllR #-}

-- | Rewrite any children of an expression of the form: @Case@ 'CoreExpr' 'Id' 'Type' [('AltCon', ['Var'], 'CoreExpr')]
caseAltAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m)
            => Rewrite c m CoreExpr
            -> Rewrite c m Id
            -> Rewrite c m Type
            -> (Int -> (Rewrite c m AltCon, (Int -> Rewrite c m Var), Rewrite c m CoreExpr))
            -> Rewrite c m CoreExpr
caseAltAnyR rsc rw rty ralts = caseAnyR rsc rw rty (\ n -> let (rcon,rvs,re) = ralts n in altAnyR rcon rvs re)
{-# INLINE caseAltAnyR #-}

-- | Rewrite one child of an expression of the form: @Case@ 'CoreExpr' 'Id' 'Type' [('AltCon', ['Var'], 'CoreExpr')]
caseAltOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m)
            => Rewrite c m CoreExpr
            -> Rewrite c m Id
            -> Rewrite c m Type
            -> (Int -> (Rewrite c m AltCon, (Int -> Rewrite c m Var), Rewrite c m CoreExpr))
            -> Rewrite c m CoreExpr
caseAltOneR rsc rw rty ralts = caseOneR rsc rw rty (\ n -> let (rcon,rvs,re) = ralts n in altOneR rcon rvs re)
{-# INLINE caseAltOneR #-}

---------------------------------------------------------------------
---------------------------------------------------------------------

-- Types

-- | Translate a type of the form: @TyVarTy@ 'TyVar'
tyVarT :: (ExtendPath c Crumb, Monad m) => Translate c m TyVar b -> Translate c m Type b
tyVarT t = translate $ \ c -> \case
                                 TyVarTy v -> apply t (c @@ TyVarTy_TyVar) v
                                 _         -> fail "not a type variable."
{-# INLINE tyVarT #-}

-- | Rewrite the 'TyVar' child of a type of the form: @TyVarTy@ 'TyVar'
tyVarR :: (ExtendPath c Crumb, Monad m) => Rewrite c m TyVar -> Rewrite c m Type
tyVarR r = tyVarT (TyVarTy <$> r)
{-# INLINE tyVarR #-}


-- | Translate a type of the form: @LitTy@ 'TyLit'
litTyT :: (ExtendPath c Crumb, Monad m) => Translate c m TyLit b -> Translate c m Type b
litTyT t = translate $ \ c -> \case
                                 LitTy x -> apply t (c @@ LitTy_TyLit) x
                                 _       -> fail "not a type literal."
{-# INLINE litTyT #-}

-- | Rewrite the 'TyLit' child of a type of the form: @LitTy@ 'TyLit'
litTyR :: (ExtendPath c Crumb, Monad m) => Rewrite c m TyLit -> Rewrite c m Type
litTyR r = litTyT (LitTy <$> r)
{-# INLINE litTyR #-}


-- | Translate a type of the form: @AppTy@ 'Type' 'Type'
appTyT :: (ExtendPath c Crumb, Monad m) => Translate c m Type a1 -> Translate c m Type a2 -> (a1 -> a2 -> b) -> Translate c m Type b
appTyT t1 t2 f = translate $ \ c -> \case
                                     AppTy ty1 ty2 -> f <$> apply t1 (c @@ AppTy_Fun) ty1 <*> apply t2 (c @@ AppTy_Arg) ty2
                                     _             -> fail "not a type application."
{-# INLINE appTyT #-}

-- | Rewrite all children of a type of the form: @AppTy@ 'Type' 'Type'
appTyAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Type -> Rewrite c m Type -> Rewrite c m Type
appTyAllR r1 r2 = appTyT r1 r2 AppTy
{-# INLINE appTyAllR #-}

-- | Rewrite any children of a type of the form: @AppTy@ 'Type' 'Type'
appTyAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Type -> Rewrite c m Type -> Rewrite c m Type
appTyAnyR r1 r2 = unwrapAnyR $ appTyAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE appTyAnyR #-}

-- | Rewrite one child of a type of the form: @AppTy@ 'Type' 'Type'
appTyOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Type -> Rewrite c m Type -> Rewrite c m Type
appTyOneR r1 r2 = unwrapOneR $ appTyAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE appTyOneR #-}


-- | Translate a type of the form: @FunTy@ 'Type' 'Type'
funTyT :: (ExtendPath c Crumb, Monad m) => Translate c m Type a1 -> Translate c m Type a2 -> (a1 -> a2 -> b) -> Translate c m Type b
funTyT t1 t2 f = translate $ \ c -> \case
                                     FunTy ty1 ty2 -> f <$> apply t1 (c @@ FunTy_Dom) ty1 <*> apply t2 (c @@ FunTy_CoDom) ty2
                                     _             -> fail "not a function type."
{-# INLINE funTyT #-}

-- | Rewrite all children of a type of the form: @FunTy@ 'Type' 'Type'
funTyAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Type -> Rewrite c m Type -> Rewrite c m Type
funTyAllR r1 r2 = funTyT r1 r2 FunTy
{-# INLINE funTyAllR #-}

-- | Rewrite any children of a type of the form: @FunTy@ 'Type' 'Type'
funTyAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Type -> Rewrite c m Type -> Rewrite c m Type
funTyAnyR r1 r2 = unwrapAnyR $ funTyAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE funTyAnyR #-}

-- | Rewrite one child of a type of the form: @FunTy@ 'Type' 'Type'
funTyOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Type -> Rewrite c m Type -> Rewrite c m Type
funTyOneR r1 r2 = unwrapOneR $ funTyAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE funTyOneR #-}


-- | Translate a type of the form: @ForAllTy@ 'Var' 'Type'
forAllTyT :: (ExtendPath c Crumb, AddBindings c, Monad m) => Translate c m Var a1 -> Translate c m Type a2 -> (a1 -> a2 -> b) -> Translate c m Type b
forAllTyT t1 t2 f = translate $ \ c -> \case
                                          ForAllTy v ty -> f <$> apply t1 (c @@ ForAllTy_Var) v <*> apply t2 (addForallBinding v c @@ ForAllTy_Body) ty
                                          _             -> fail "not a forall type."
{-# INLINE forAllTyT #-}

-- | Rewrite all children of a type of the form: @ForAllTy@ 'Var' 'Type'
forAllTyAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => Rewrite c m Var -> Rewrite c m Type -> Rewrite c m Type
forAllTyAllR r1 r2 = forAllTyT r1 r2 ForAllTy
{-# INLINE forAllTyAllR #-}

-- | Rewrite any children of a type of the form: @ForAllTy@ 'Var' 'Type'
forAllTyAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Var -> Rewrite c m Type -> Rewrite c m Type
forAllTyAnyR r1 r2 = unwrapAnyR $ forAllTyAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE forAllTyAnyR #-}

-- | Rewrite one child of a type of the form: @ForAllTy@ 'Var' 'Type'
forAllTyOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Var -> Rewrite c m Type -> Rewrite c m Type
forAllTyOneR r1 r2 = unwrapOneR $ forAllTyAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE forAllTyOneR #-}


-- | Translate a type of the form: @TyConApp@ 'TyCon' ['KindOrType']
tyConAppT :: (ExtendPath c Crumb, Monad m) => Translate c m TyCon a1 -> (Int -> Translate c m KindOrType a2) -> (a1 -> [a2] -> b) -> Translate c m Type b
tyConAppT t ts f = translate $ \ c -> \case
                                         TyConApp con tys -> f <$> apply t (c @@ TyConApp_TyCon) con <*> sequence [ apply (ts n) (c @@ TyConApp_Arg n) ty | (ty,n) <- zip tys [0..] ]
                                         _                -> fail "not a type-constructor application."
{-# INLINE tyConAppT #-}

-- | Rewrite all children of a type of the form: @TyConApp@ 'TyCon' ['KindOrType']
tyConAppAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m TyCon -> (Int -> Rewrite c m KindOrType) -> Rewrite c m Type
tyConAppAllR r rs = tyConAppT r rs TyConApp
{-# INLINE tyConAppAllR #-}

-- | Rewrite any children of a type of the form: @TyConApp@ 'TyCon' ['KindOrType']
tyConAppAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m TyCon -> (Int -> Rewrite c m KindOrType) -> Rewrite c m Type
tyConAppAnyR r rs = unwrapAnyR $ tyConAppAllR (wrapAnyR r) (wrapAnyR . rs)
{-# INLINE tyConAppAnyR #-}

-- | Rewrite one child of a type of the form: @TyConApp@ 'TyCon' ['KindOrType']
tyConAppOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m TyCon -> (Int -> Rewrite c m KindOrType) -> Rewrite c m Type
tyConAppOneR r rs = unwrapOneR $ tyConAppAllR (wrapOneR r) (wrapOneR . rs)
{-# INLINE tyConAppOneR #-}

---------------------------------------------------------------------
---------------------------------------------------------------------

-- Coercions
-- TODO: review and bring all these up-to-date for Coercions w/ Roles in 7.8

#if __GLASGOW_HASKELL__ > 706
-- | Translate a coercion of the form: @Refl@ 'Role' 'Type'
reflT :: (ExtendPath c Crumb, Monad m) => Translate c m Type a1 -> (Role -> a1 -> b) -> Translate c m Coercion b
reflT t f = translate $ \ c -> \case
                                 Refl r ty -> f r <$> apply t (c @@ Refl_Type) ty
                                 _         -> fail "not a reflexive coercion."

-- | Rewrite the 'Type' child of a coercion of the form: @Refl@ 'Role' 'Type'
reflR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Type -> Rewrite c m Coercion
reflR r = reflT r Refl
#else
-- | Translate a coercion of the form: @Refl@ 'Type'
reflT :: (ExtendPath c Crumb, Monad m) => Translate c m Type b -> Translate c m Coercion b
reflT t = translate $ \ c -> \case
                                 Refl ty -> apply t (c @@ Refl_Type) ty
                                 _       -> fail "not a reflexive coercion."

-- | Rewrite the 'Type' child of a coercion of the form: @Refl@ 'Type'
reflR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Type -> Rewrite c m Coercion
reflR r = reflT (Refl <$> r)
#endif
{-# INLINE reflT #-}
{-# INLINE reflR #-}

#if __GLASGOW_HASKELL__ > 706
-- | Translate a coercion of the form: @TyConAppCo@ 'Role' 'TyCon' ['Coercion']
tyConAppCoT :: (ExtendPath c Crumb, Monad m) => Translate c m TyCon a1 -> (Int -> Translate c m Coercion a2) -> (Role -> a1 -> [a2] -> b) -> Translate c m Coercion b
tyConAppCoT t ts f = translate $ \ c -> \case
                                           TyConAppCo r con coes -> f r <$> apply t (c @@ TyConAppCo_TyCon) con <*> sequence [ apply (ts n) (c @@ TyConAppCo_Arg n) co | (co,n) <- zip coes [0..] ]
                                           _                     -> fail "not a type-constructor coercion."
#else
-- | Translate a coercion of the form: @TyConAppCo@ 'TyCon' ['Coercion']
tyConAppCoT :: (ExtendPath c Crumb, Monad m) => Translate c m TyCon a1 -> (Int -> Translate c m Coercion a2) -> (a1 -> [a2] -> b) -> Translate c m Coercion b
tyConAppCoT t ts f = translate $ \ c -> \case
                                           TyConAppCo con coes -> f <$> apply t (c @@ TyConAppCo_TyCon) con <*> sequence [ apply (ts n) (c @@ TyConAppCo_Arg n) co | (co,n) <- zip coes [0..] ]
                                           _                   -> fail "not a type-constructor coercion."
#endif
{-# INLINE tyConAppCoT #-}

-- | Rewrite all children of a coercion of the form: @TyConAppCo@ 'TyCon' ['Coercion']
tyConAppCoAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m TyCon -> (Int -> Rewrite c m Coercion) -> Rewrite c m Coercion
tyConAppCoAllR r rs = tyConAppCoT r rs TyConAppCo
{-# INLINE tyConAppCoAllR #-}

-- | Rewrite any children of a coercion of the form: @TyConAppCo@ 'TyCon' ['Coercion']
tyConAppCoAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m TyCon -> (Int -> Rewrite c m Coercion) -> Rewrite c m Coercion
tyConAppCoAnyR r rs = unwrapAnyR $ tyConAppCoAllR (wrapAnyR r) (wrapAnyR . rs)
{-# INLINE tyConAppCoAnyR #-}

-- | Rewrite one child of a coercion of the form: @TyConAppCo@ 'TyCon' ['Coercion']
tyConAppCoOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m TyCon -> (Int -> Rewrite c m Coercion) -> Rewrite c m Coercion
tyConAppCoOneR r rs = unwrapOneR $ tyConAppCoAllR (wrapOneR r) (wrapOneR . rs)
{-# INLINE tyConAppCoOneR #-}


-- | Translate a coercion of the form: @AppCo@ 'Coercion' 'Coercion'
appCoT :: (ExtendPath c Crumb, Monad m) => Translate c m Coercion a1 -> Translate c m Coercion a2 -> (a1 -> a2 -> b) -> Translate c m Coercion b
appCoT t1 t2 f = translate $ \ c -> \case
                                     AppCo co1 co2 -> f <$> apply t1 (c @@ AppCo_Fun) co1 <*> apply t2 (c @@ AppCo_Arg) co2
                                     _             -> fail "not a coercion application."
{-# INLINE appCoT #-}

-- | Rewrite all children of a coercion of the form: @AppCo@ 'Coercion' 'Coercion'
appCoAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Coercion -> Rewrite c m Coercion -> Rewrite c m Coercion
appCoAllR r1 r2 = appCoT r1 r2 AppCo
{-# INLINE appCoAllR #-}

-- | Rewrite any children of a coercion of the form: @AppCo@ 'Coercion' 'Coercion'
appCoAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Coercion -> Rewrite c m Coercion -> Rewrite c m Coercion
appCoAnyR r1 r2 = unwrapAnyR $ appCoAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE appCoAnyR #-}

-- | Rewrite one child of a coercion of the form: @AppCo@ 'Coercion' 'Coercion'
appCoOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Coercion -> Rewrite c m Coercion -> Rewrite c m Coercion
appCoOneR r1 r2 = unwrapOneR $ appCoAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE appCoOneR #-}


-- | Translate a coercion of the form: @ForAllCo@ 'TyVar' 'Coercion'
forAllCoT :: (ExtendPath c Crumb, AddBindings c, Monad m) => Translate c m TyVar a1 -> Translate c m Coercion a2 -> (a1 -> a2 -> b) -> Translate c m Coercion b
forAllCoT t1 t2 f = translate $ \ c -> \case
                                          ForAllCo v co -> f <$> apply t1 (c @@ ForAllCo_TyVar) v <*> apply t2 (addForallBinding v c @@ ForAllCo_Body) co
                                          _             -> fail "not a forall coercion."
{-# INLINE forAllCoT #-}

-- | Rewrite all children of a coercion of the form: @ForAllCo@ 'TyVar' 'Coercion'
forAllCoAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => Rewrite c m TyVar -> Rewrite c m Coercion -> Rewrite c m Coercion
forAllCoAllR r1 r2 = forAllCoT r1 r2 ForAllCo
{-# INLINE forAllCoAllR #-}

-- | Rewrite any children of a coercion of the form: @ForAllCo@ 'TyVar' 'Coercion'
forAllCoAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m TyVar -> Rewrite c m Coercion -> Rewrite c m Coercion
forAllCoAnyR r1 r2 = unwrapAnyR $ forAllCoAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE forAllCoAnyR #-}

-- | Rewrite one child of a coercion of the form: @ForAllCo@ 'TyVar' 'Coercion'
forAllCoOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m TyVar -> Rewrite c m Coercion -> Rewrite c m Coercion
forAllCoOneR r1 r2 = unwrapOneR $ forAllCoAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE forAllCoOneR #-}


-- | Translate a coercion of the form: @CoVarCo@ 'CoVar'
coVarCoT :: (ExtendPath c Crumb, Monad m) => Translate c m CoVar b -> Translate c m Coercion b
coVarCoT t = translate $ \ c -> \case
                                   CoVarCo v -> apply t (c @@ CoVarCo_CoVar) v
                                   _         -> fail "not a coercion variable."
{-# INLINE coVarCoT #-}

-- | Rewrite the 'CoVar' child of a coercion of the form: @CoVarCo@ 'CoVar'
coVarCoR :: (ExtendPath c Crumb, Monad m) => Rewrite c m CoVar -> Rewrite c m Coercion
coVarCoR r = coVarCoT (CoVarCo <$> r)
{-# INLINE coVarCoR #-}

#if __GLASGOW_HASKELL__ > 706
-- | Translate a coercion of the form: @AxiomInstCo@ ('CoAxiom' 'Branched') 'BranchIndex' ['Coercion']
axiomInstCoT :: (ExtendPath c Crumb, Monad m) => Translate c m (CoAxiom Branched) a1 -> Translate c m BranchIndex a2 -> (Int -> Translate c m Coercion a3) -> (a1 -> a2 -> [a3] -> b) -> Translate c m Coercion b
axiomInstCoT t1 t2 ts f = translate $ \ c -> \case
                                                AxiomInstCo ax idx coes -> f <$> apply t1 (c @@ AxiomInstCo_Axiom) ax <*> apply t2 (c @@ AxiomInstCo_Index) idx <*> sequence [ apply (ts n) (c @@ AxiomInstCo_Arg n) co | (co,n) <- zip coes [0..] ]
                                                _                       -> fail "not a coercion axiom instantiation."
#else
-- | Translate a coercion of the form: @AxiomInstCo@ 'CoAxiom' ['Coercion']
axiomInstCoT :: (ExtendPath c Crumb, Monad m) => Translate c m CoAxiom a1 -> (Int -> Translate c m Coercion a2) -> (a1 -> [a2] -> b) -> Translate c m Coercion b
axiomInstCoT t ts f = translate $ \ c -> \case
                                            AxiomInstCo ax coes -> f <$> apply t (c @@ AxiomInstCo_Axiom) ax <*> sequence [ apply (ts n) (c @@ AxiomInstCo_Arg n) co | (co,n) <- zip coes [0..] ]
                                            _                   -> fail "not a coercion axiom instantiation."
#endif
{-# INLINE axiomInstCoT #-}

#if __GLASGOW_HASKELL__ > 706
-- | Rewrite all children of a coercion of the form: @AxiomInstCo@ ('CoAxiom' 'Branched') 'BranchIndex' ['Coercion']
axiomInstCoAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m (CoAxiom Branched) -> Rewrite c m BranchIndex -> (Int -> Rewrite c m Coercion) -> Rewrite c m Coercion
axiomInstCoAllR r1 r2 rs = axiomInstCoT r1 r2 rs AxiomInstCo
#else
-- | Rewrite all children of a coercion of the form: @AxiomInstCo@ 'CoAxiom' ['Coercion']
axiomInstCoAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m CoAxiom -> (Int -> Rewrite c m Coercion) -> Rewrite c m Coercion
axiomInstCoAllR r rs = axiomInstCoT r rs AxiomInstCo
#endif
{-# INLINE axiomInstCoAllR #-}

#if __GLASGOW_HASKELL__ > 706
-- | Rewrite any children of a coercion of the form: @AxiomInstCo@ ('CoAxiom' 'Branched') 'BranchIndex' ['Coercion']
axiomInstCoAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m (CoAxiom Branched) -> Rewrite c m BranchIndex -> (Int -> Rewrite c m Coercion) -> Rewrite c m Coercion
axiomInstCoAnyR r1 r2 rs = unwrapAnyR $ axiomInstCoAllR (wrapAnyR r1) (wrapAnyR r2) (wrapAnyR . rs)
#else
-- | Rewrite any children of a coercion of the form: @AxiomInstCo@ 'CoAxiom' ['Coercion']
axiomInstCoAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m CoAxiom -> (Int -> Rewrite c m Coercion) -> Rewrite c m Coercion
axiomInstCoAnyR r rs = unwrapAnyR $ axiomInstCoAllR (wrapAnyR r) (wrapAnyR . rs)
#endif
{-# INLINE axiomInstCoAnyR #-}

#if __GLASGOW_HASKELL__ > 706
-- | Rewrite one child of a coercion of the form: @AxiomInstCo@ ('CoAxiom' 'Branched') 'BranchIndex' ['Coercion']
axiomInstCoOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m (CoAxiom Branched) -> Rewrite c m BranchIndex -> (Int -> Rewrite c m Coercion) -> Rewrite c m Coercion
axiomInstCoOneR r1 r2 rs = unwrapOneR $ axiomInstCoAllR (wrapOneR r1) (wrapOneR r2) (wrapOneR . rs)
#else
-- | Rewrite one child of a coercion of the form: @AxiomInstCo@ 'CoAxiom' ['Coercion']
axiomInstCoOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m CoAxiom -> (Int -> Rewrite c m Coercion) -> Rewrite c m Coercion
axiomInstCoOneR r rs = unwrapOneR $ axiomInstCoAllR (wrapOneR r) (wrapOneR . rs)
#endif
{-# INLINE axiomInstCoOneR #-}

#if __GLASGOW_HASKELL__ > 706
#else
-- | Translate a coercion of the form: @UnsafeCo@ 'Type' 'Type'
unsafeCoT :: (ExtendPath c Crumb, Monad m) => Translate c m Type a1 -> Translate c m Type a2 -> (a1 -> a2 -> b) -> Translate c m Coercion b
unsafeCoT t1 t2 f = translate $ \ c -> \case
                                          UnsafeCo ty1 ty2 -> f <$> apply t1 (c @@ UnsafeCo_Left) ty1 <*> apply t2 (c @@ UnsafeCo_Right) ty2
                                          _                -> fail "not an unsafe coercion."
{-# INLINE unsafeCoT #-}

-- | Rewrite all children of a coercion of the form: @UnsafeCo@ 'Type' 'Type'
unsafeCoAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Type -> Rewrite c m Type -> Rewrite c m Coercion
unsafeCoAllR r1 r2 = unsafeCoT r1 r2 UnsafeCo
{-# INLINE unsafeCoAllR #-}

-- | Rewrite any children of a coercion of the form: @UnsafeCo@ 'Type' 'Type'
unsafeCoAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Type -> Rewrite c m Type -> Rewrite c m Coercion
unsafeCoAnyR r1 r2 = unwrapAnyR $ unsafeCoAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE unsafeCoAnyR #-}

-- | Rewrite one child of a coercion of the form: @UnsafeCo@ 'Type' 'Type'
unsafeCoOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Type -> Rewrite c m Type -> Rewrite c m Coercion
unsafeCoOneR r1 r2 = unwrapOneR $ unsafeCoAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE unsafeCoOneR #-}
#endif

-- | Translate a coercion of the form: @SymCo@ 'Coercion'
symCoT :: (ExtendPath c Crumb, Monad m) => Translate c m Coercion b -> Translate c m Coercion b
symCoT t = translate $ \ c -> \case
                                   SymCo co -> apply t (c @@ SymCo_Co) co
                                   _        -> fail "not a symmetric coercion."
{-# INLINE symCoT #-}

-- | Rewrite the 'Coercion' child of a coercion of the form: @SymCo@ 'Coercion'
symCoR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Coercion -> Rewrite c m Coercion
symCoR r = symCoT (SymCo <$> r)
{-# INLINE symCoR #-}


-- | Translate a coercion of the form: @TransCo@ 'Coercion' 'Coercion'
transCoT :: (ExtendPath c Crumb, Monad m) => Translate c m Coercion a1 -> Translate c m Coercion a2 -> (a1 -> a2 -> b) -> Translate c m Coercion b
transCoT t1 t2 f = translate $ \ c -> \case
                                          TransCo co1 co2 -> f <$> apply t1 (c @@ TransCo_Left) co1 <*> apply t2 (c @@ TransCo_Right) co2
                                          _               -> fail "not a transitive coercion."
{-# INLINE transCoT #-}

-- | Rewrite all children of a coercion of the form: @TransCo@ 'Coercion' 'Coercion'
transCoAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Coercion -> Rewrite c m Coercion -> Rewrite c m Coercion
transCoAllR r1 r2 = transCoT r1 r2 TransCo
{-# INLINE transCoAllR #-}

-- | Rewrite any children of a coercion of the form: @TransCo@ 'Coercion' 'Coercion'
transCoAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Coercion -> Rewrite c m Coercion -> Rewrite c m Coercion
transCoAnyR r1 r2 = unwrapAnyR $ transCoAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE transCoAnyR #-}

-- | Rewrite one child of a coercion of the form: @TransCo@ 'Coercion' 'Coercion'
transCoOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Coercion -> Rewrite c m Coercion -> Rewrite c m Coercion
transCoOneR r1 r2 = unwrapOneR $ transCoAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE transCoOneR #-}


-- | Translate a coercion of the form: @NthCo@ 'Int' 'Coercion'
nthCoT :: (ExtendPath c Crumb, Monad m) => Translate c m Int a1 -> Translate c m Coercion a2 -> (a1 -> a2 -> b) -> Translate c m Coercion b
nthCoT t1 t2 f = translate $ \ c -> \case
                                          NthCo n co -> f <$> apply t1 (c @@ NthCo_Int) n <*> apply t2 (c @@ NthCo_Co) co
                                          _          -> fail "not an Nth coercion."
{-# INLINE nthCoT #-}

-- | Rewrite all children of a coercion of the form: @NthCo@ 'Int' 'Coercion'
nthCoAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Int -> Rewrite c m Coercion -> Rewrite c m Coercion
nthCoAllR r1 r2 = nthCoT r1 r2 NthCo
{-# INLINE nthCoAllR #-}

-- | Rewrite any children of a coercion of the form: @NthCo@ 'Int' 'Coercion'
nthCoAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Int -> Rewrite c m Coercion -> Rewrite c m Coercion
nthCoAnyR r1 r2 = unwrapAnyR $ nthCoAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE nthCoAnyR #-}

-- | Rewrite one child of a coercion of the form: @NthCo@ 'Int' 'Coercion'
nthCoOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Int -> Rewrite c m Coercion -> Rewrite c m Coercion
nthCoOneR r1 r2 = unwrapOneR $ nthCoAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE nthCoOneR #-}


#if __GLASGOW_HASKELL__ > 706
-- | Translate a coercion of the form: @LRCo@ 'LeftOrRight' 'Coercion'
lrCoT :: (ExtendPath c Crumb, Monad m) => Translate c m LeftOrRight a1 -> Translate c m Coercion a2 -> (a1 -> a2 -> b) -> Translate c m Coercion b
lrCoT t1 t2 f = translate $ \ c -> \case
                                      LRCo lr co -> f <$> apply t1 (c @@ LRCo_LR) lr <*> apply t2 (c @@ LRCo_Co) co
                                      _          -> fail "not a left/right coercion."
{-# INLINE lrCoT #-}

-- | Translate all children of a coercion of the form: @LRCo@ 'LeftOrRight' 'Coercion'
lrCoAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m LeftOrRight -> Rewrite c m Coercion -> Rewrite c m Coercion
lrCoAllR r1 r2 = lrCoT r1 r2 LRCo
{-# INLINE lrCoAllR #-}

-- | Translate any children of a coercion of the form: @LRCo@ 'LeftOrRight' 'Coercion'
lrCoAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m LeftOrRight -> Rewrite c m Coercion -> Rewrite c m Coercion
lrCoAnyR r1 r2 = unwrapAnyR $ lrCoAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE lrCoAnyR #-}

-- | Translate one child of a coercion of the form: @LRCo@ 'LeftOrRight' 'Coercion'
lrCoOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m LeftOrRight -> Rewrite c m Coercion -> Rewrite c m Coercion
lrCoOneR r1 r2 = unwrapOneR $ lrCoAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE lrCoOneR #-}
#else
#endif


-- | Translate a coercion of the form: @InstCo@ 'Coercion' 'Type'
instCoT :: (ExtendPath c Crumb, Monad m) => Translate c m Coercion a1 -> Translate c m Type a2 -> (a1 -> a2 -> b) -> Translate c m Coercion b
instCoT t1 t2 f = translate $ \ c -> \case
                                          InstCo co ty -> f <$> apply t1 (c @@ InstCo_Co) co <*> apply t2 (c @@ InstCo_Type) ty
                                          _            -> fail "not a coercion instantiation."
{-# INLINE instCoT #-}

-- | Rewrite all children of a coercion of the form: @InstCo@ 'Coercion' 'Type'
instCoAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Coercion -> Rewrite c m Type -> Rewrite c m Coercion
instCoAllR r1 r2 = instCoT r1 r2 InstCo
{-# INLINE instCoAllR #-}

-- | Rewrite any children of a coercion of the form: @InstCo@ 'Coercion' 'Type'
instCoAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Coercion -> Rewrite c m Type -> Rewrite c m Coercion
instCoAnyR r1 r2 = unwrapAnyR $ instCoAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE instCoAnyR #-}

-- | Rewrite one child of a coercion of the form: @InstCo@ 'Coercion' 'Type'
instCoOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Coercion -> Rewrite c m Type -> Rewrite c m Coercion
instCoOneR r1 r2 = unwrapOneR $ instCoAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE instCoOneR #-}

---------------------------------------------------------------------
---------------------------------------------------------------------

-- | Earlier versions of HERMIT used 'Int' as the crumb type.
--   This translation maps an 'Int' to the corresponding 'Crumb', for backwards compatibility purposes.
deprecatedIntToCrumbT :: Monad m => Int -> Translate c m Core Crumb
deprecatedIntToCrumbT n = contextfreeT $ \case
                                            GutsCore _                 | n == 0                        -> return ModGuts_Prog
                                            AltCore _                  | n == 0                        -> return Alt_RHS
                                            DefCore _                  | n == 0                        -> return Def_RHS
                                            ProgCore (ProgCons _ _)    | n == 0                        -> return ProgCons_Head
                                                                       | n == 1                        -> return ProgCons_Tail
                                            BindCore (NonRec _ _)      | n == 0                        -> return NonRec_RHS
                                            BindCore (Rec bds)         | (n >= 0) && (n < length bds)  -> return (Rec_Def n)
                                            ExprCore (App _ _)         | n == 0                        -> return App_Fun
                                                                       | n == 1                        -> return App_Arg
                                            ExprCore (Lam _ _)         | n == 0                        -> return Lam_Body
                                            ExprCore (Let _ _)         | n == 0                        -> return Let_Bind
                                                                       | n == 1                        -> return Let_Body
                                            ExprCore (Case _ _ _ alts) | n == 0                        -> return Case_Scrutinee
                                                                       | (n > 0) && (n <= length alts) -> return (Case_Alt (n-1))
                                            ExprCore (Cast _ _)        | n == 0                        -> return Cast_Expr
                                            ExprCore (Tick _ _)        | n == 0                        -> return Tick_Expr
                                            _                                                          -> fail ("Child " ++ show n ++ " does not exist.")
{-# INLINE deprecatedIntToCrumbT #-}

-- | Builds a path to the first child, based on the old numbering system.
deprecatedIntToPathT :: Monad m => Int -> Translate c m Core LocalPathH
deprecatedIntToPathT =  liftM (mempty @@) . deprecatedIntToCrumbT
{-# INLINE deprecatedIntToPathT #-}

---------------------------------------------------------------------
---------------------------------------------------------------------
