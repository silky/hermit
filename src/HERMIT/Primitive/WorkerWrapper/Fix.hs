module HERMIT.Primitive.WorkerWrapper.Fix
       ( -- * The Worker/Wrapper Transformation
         -- | Note that many of these operations require 'Data.Function.fix' to be in scope.
         HERMIT.Primitive.WorkerWrapper.Fix.externals
       , workerWrapperFacBR
       , workerWrapperSplitR
       , workerWrapperSplitParam
       , workerWrapperGenerateFusionR
       , workerWrapperFusionBR
       , wwAssA
       , wwAssB
       , wwAssC
       )
where

import GhcPlugins as GHC hiding (varName)

import Control.Applicative
import Control.Arrow

import HERMIT.Core
import HERMIT.Monad
import HERMIT.Kure
import HERMIT.External
import HERMIT.GHC
import HERMIT.Utilities

import HERMIT.Primitive.AlphaConversion
import HERMIT.Primitive.Common
import HERMIT.Primitive.Function
import HERMIT.Primitive.Local
import HERMIT.Primitive.Navigation
import HERMIT.Primitive.New -- TODO: Sort out heirarchy
import HERMIT.Primitive.FixPoint
import HERMIT.Primitive.Unfold

import HERMIT.Primitive.WorkerWrapper.Common

import qualified Language.Haskell.TH as TH

--------------------------------------------------------------------------------------------------

-- | Externals for manipulating fixed points, and for the worker/wrapper transformation.
externals ::  [External]
externals =
         [
           external "ww-factorisation" ((\ wrap unwrap assC -> promoteExprBiR $ workerWrapperFac (mkWWAssC assC) wrap unwrap)
                                          :: CoreString -> CoreString -> RewriteH Core -> BiRewriteH Core)
                [ "Worker/Wrapper Factorisation",
                  "For any \"f :: A -> A\", and given \"wrap :: B -> A\" and \"unwrap :: A -> B\" as arguments,",
                  "and a proof of Assumption C (fix A (\\ a -> wrap (unwrap (f a))) ==> fix A f), then",
                  "fix A f  ==>  wrap (fix B (\\ b -> unwrap (f (wrap b))))"
                ] .+ Introduce .+ Context
         , external "ww-factorisation-unsafe" ((\ wrap unwrap -> promoteExprBiR $ workerWrapperFac Nothing wrap unwrap)
                                               :: CoreString -> CoreString -> BiRewriteH Core)
                [ "Unsafe Worker/Wrapper Factorisation",
                  "For any \"f :: A -> A\", and given \"wrap :: B -> A\" and \"unwrap :: A -> B\" as arguments, then",
                  "fix A f  <==>  wrap (fix B (\\ b -> unwrap (f (wrap b))))",
                  "Note: the pre-condition \"fix A (\\ a -> wrap (unwrap (f a))) == fix A f\" is expected to hold."
                ] .+ Introduce .+ Context .+ PreCondition
         , external "ww-split" ((\ wrap unwrap assC -> promoteDefR $ workerWrapperSplit (mkWWAssC assC) wrap unwrap)
                                  :: CoreString -> CoreString -> RewriteH Core -> RewriteH Core)
                [ "Worker/Wrapper Split",
                  "For any \"prog :: A\", and given \"wrap :: B -> A\" and \"unwrap :: A -> B\" as arguments,",
                  "and a proof of Assumption C (fix A (\\ a -> wrap (unwrap (f a))) ==> fix A f), then",
                  "prog = expr  ==>  prog = let f = \\ prog -> expr",
                  "                          in let work = unwrap (f (wrap work))",
                  "                              in wrap work"
                ] .+ Introduce .+ Context
         , external "ww-split-unsafe" ((\ wrap unwrap -> promoteDefR $ workerWrapperSplit Nothing wrap unwrap)
                                       :: CoreString -> CoreString -> RewriteH Core)
                [ "Unsafe Worker/Wrapper Split",
                  "For any \"prog :: A\", and given \"wrap :: B -> A\" and \"unwrap :: A -> B\" as arguments, then",
                  "prog = expr  ==>  prog = let f = \\ prog -> expr",
                  "                          in let work = unwrap (f (wrap work))",
                  "                              in wrap work",
                  "Note: the pre-condition \"fix A (wrap . unwrap . f) == fix A f\" is expected to hold."
                ] .+ Introduce .+ Context .+ PreCondition
         , external "ww-split-param" ((\ n wrap unwrap assC -> promoteDefR $ workerWrapperSplitParam n (mkWWAssC assC) wrap unwrap)
                                      :: Int -> CoreString -> CoreString -> RewriteH Core -> RewriteH Core)
                [ "Worker/Wrapper Split - Type Paramater Variant",
                  "For any \"prog :: forall t1 t2 .. tn . A\",",
                  "and given \"wrap :: forall t1 t2 .. tn . B -> A\" and \"unwrap :: forall t1 t2 .. tn . A -> B\" as arguments,",
                  "and a proof of Assumption C (forall t1 t2 .. tn . fix A (wrap t1 t2 .. tn . unwrap t1 t2 .. tn . f) ==> fix A f), then",
                  "prog = expr  ==>  prog = \\ t1 t2 .. tn -> let f = \\ prog -> expr t1 t2 .. tn",
                  "                                            in let work = unwrap t1 t2 .. tn (f (wrap t1 t2  ..tn work))",
                  "                                                in wrap t1 t2 .. tn work"
                ] .+ Introduce .+ Context .+ PreCondition .+ TODO .+ Experiment
         , external "ww-split-param-unsafe" ((\ n wrap unwrap -> promoteDefR $ workerWrapperSplitParam n Nothing wrap unwrap)
                                             :: Int -> CoreString -> CoreString -> RewriteH Core)
                [ "Unsafe Worker/Wrapper Split - Type Paramater Variant",
                  "For any \"prog :: forall t1 t2 .. tn . A\",",
                  "and given \"wrap :: forall t1 t2 .. tn . B -> A\" and \"unwrap :: forall t1 t2 .. tn . A -> B\" as arguments, then",
                  "prog = expr  ==>  prog = \\ t1 t2 .. tn -> let f = \\ prog -> expr t1 t2 .. tn",
                  "                                            in let work = unwrap t1 t2 .. tn (f (wrap t1 t2  ..tn work))",
                  "                                                in wrap t1 t2 .. tn work",
                  "Note: the pre-condition \"forall t1 t2 .. tn . fix A (wrap t1 t2 .. tn . unwrap t1 t2 .. tn . f) == fix A f\" is expected to hold."
                ] .+ Introduce .+ Context .+ PreCondition .+ TODO .+ Experiment
         , external "ww-assumption-A" ((\ wrap unwrap assA -> promoteExprBiR $ wwA (Just $ extractR assA) wrap unwrap)
                                       :: CoreString -> CoreString -> RewriteH Core -> BiRewriteH Core)
                [ "Worker/Wrapper Assumption A",
                  "For a \"wrap :: B -> A\" and an \"unwrap :: A -> B\",",
                  "and given a proof of \"wrap (unwrap a) ==> a\", then",
                  "wrap (unwrap a)  <==>  a"
                ] .+ Introduce .+ Context
         , external "ww-assumption-B" ((\ wrap unwrap f assB -> promoteExprBiR $ wwB (Just $ extractR assB) wrap unwrap f)
                                       :: CoreString -> CoreString -> CoreString -> RewriteH Core -> BiRewriteH Core)
                [ "Worker/Wrapper Assumption B",
                  "For a \"wrap :: B -> A\", an \"unwrap :: A -> B\", and an \"f :: A -> A\",",
                  "and given a proof of \"wrap (unwrap (f a)) ==> f a\", then",
                  "wrap (unwrap (f a))  <==>  f a"
                ] .+ Introduce .+ Context
         , external "ww-assumption-C" ((\ wrap unwrap f assC -> promoteExprBiR $ wwC (Just $ extractR assC) wrap unwrap f)
                                       :: CoreString -> CoreString -> CoreString -> RewriteH Core -> BiRewriteH Core)
                [ "Worker/Wrapper Assumption C",
                  "For a \"wrap :: B -> A\", an \"unwrap :: A -> B\", and an \"f :: A -> A\",",
                  "and given a proof of \"fix A (\\ a -> wrap (unwrap (f a))) ==> fix A f\", then",
                  "fix A (\\ a -> wrap (unwrap (f a)))  <==>  fix A f"
                ] .+ Introduce .+ Context
         , external "ww-assumption-A-unsafe" ((\ wrap unwrap -> promoteExprBiR $ wwA Nothing wrap unwrap)
                                              :: CoreString -> CoreString -> BiRewriteH Core)
                [ "Unsafe Worker/Wrapper Assumption A",
                  "For a \"wrap :: B -> A\" and an \"unwrap :: A -> B\", then",
                  "wrap (unwrap a)  <==>  a",
                  "Note: only use this if it's true!"
                ] .+ Introduce .+ Context .+ PreCondition
         , external "ww-assumption-B-unsafe" ((\ wrap unwrap f -> promoteExprBiR $ wwB Nothing wrap unwrap f)
                                              :: CoreString -> CoreString -> CoreString -> BiRewriteH Core)
                [ "Unsafe Worker/Wrapper Assumption B",
                  "For a \"wrap :: B -> A\", an \"unwrap :: A -> B\", and an \"f :: A -> A\", then",
                  "wrap (unwrap (f a))  <==>  f a",
                  "Note: only use this if it's true!"
                ] .+ Introduce .+ Context .+ PreCondition
         , external "ww-assumption-C-unsafe" ((\ wrap unwrap f -> promoteExprBiR $ wwC Nothing wrap unwrap f)
                                              :: CoreString -> CoreString -> CoreString -> BiRewriteH Core)
                [ "Unsafe Worker/Wrapper Assumption C",
                  "For a \"wrap :: B -> A\", an \"unwrap :: A -> B\", and an \"f :: A -> A\", then",
                  "fix A (\\ a -> wrap (unwrap (f a)))  <==>  fix A f",
                  "Note: only use this if it's true!"
                ] .+ Introduce .+ Context .+ PreCondition
         , external "ww-AssA-to-AssB" (promoteExprR . wwAssAimpliesAssB . extractR :: RewriteH Core -> RewriteH Core)
                   [ "Convert a proof of worker/wrapper Assumption A into a proof of worker/wrapper Assumption B."
                   ]
         , external "ww-AssB-to-AssC" (promoteExprR . wwAssBimpliesAssC . extractR :: RewriteH Core -> RewriteH Core)
                   [ "Convert a proof of worker/wrapper Assumption B into a proof of worker/wrapper Assumption C."
                   ]
         , external "ww-AssA-to-AssC" (promoteExprR . wwAssAimpliesAssC . extractR :: RewriteH Core -> RewriteH Core)
                   [ "Convert a proof of worker/wrapper Assumption A into a proof of worker/wrapper Assumption C."
                   ]
         , external "ww-generate-fusion" (workerWrapperGenerateFusionR . mkWWAssC :: RewriteH Core -> RewriteH Core)
                   [ "Given a proof of Assumption C (fix A (\\ a -> wrap (unwrap (f a))) ==> fix A f), then",
                     "execute this command on \"work = unwrap (f (wrap work))\" to enable the \"ww-fusion\" rule thereafter.",
                     "Note that this is performed automatically as part of \"ww-split\"."
                   ] .+ Experiment .+ TODO
         , external "ww-generate-fusion-unsafe" (workerWrapperGenerateFusionR Nothing :: RewriteH Core)
                   [ "Execute this command on \"work = unwrap (f (wrap work))\" to enable the \"ww-fusion\" rule thereafter.",
                     "The precondition \"fix A (wrap . unwrap . f) == fix A f\" is expected to hold.",
                     "Note that this is performed automatically as part of \"ww-split\"."
                   ] .+ Experiment .+ TODO
         , external "ww-fusion" (promoteExprBiR workerWrapperFusion :: BiRewriteH Core)
                [ "Worker/Wrapper Fusion",
                  "unwrap (wrap work)  <==>  work",
                  "Note: you are required to have previously executed the command \"ww-generate-fusion\" on the definition",
                  "      work = unwrap (f (wrap work))"
                ] .+ Introduce .+ Context .+ PreCondition .+ TODO
         ]
  where
    mkWWAssC :: RewriteH Core -> Maybe WWAssumption
    mkWWAssC r = Just (WWAssumption C (extractR r))

--------------------------------------------------------------------------------------------------

-- | For any @f :: A -> A@, and given @wrap :: B -> A@ and @unwrap :: A -> B@ as arguments, then
--   @fix A f@  \<==\>  @wrap (fix B (\\ b -> unwrap (f (wrap b))))@
workerWrapperFacBR :: Maybe WWAssumption -> CoreExpr -> CoreExpr -> BiRewriteH CoreExpr
workerWrapperFacBR mAss wrap unwrap = beforeBiR (wrapUnwrapTypes wrap unwrap)
                                                (\ (tyA,tyB) -> bidirectional (wwL tyA tyB) wwR)
  where
    wwL :: Type -> Type -> RewriteH CoreExpr
    wwL tyA tyB = prefixFailMsg "worker/wrapper factorisation failed: " $
                  do (tA,f) <- isFixExpr
                     guardMsg (eqType tyA tA) ("wrapper/unwrapper types do not match fix body type.")
                     whenJust (verifyWWAss wrap unwrap f) mAss
                     b <- constT (newIdH "x" tyB)
                     App wrap <$> mkFix (Lam b (App unwrap (App f (App wrap (Var b)))))

    wwR :: RewriteH CoreExpr
    wwR  =    prefixFailMsg "(reverse) worker/wrapper factorisation failed: " $
              withPatFailMsg "not an application." $
              do App wrap2 fx <- idR
                 withPatFailMsg wrongFixBody $
                   do (_, Lam b (App unwrap1 (App f (App wrap1 (Var b'))))) <- isFixExpr <<< constant fx
                      guardMsg (b == b') wrongFixBody
                      guardMsg (equivalentBy exprAlphaEq [wrap, wrap1, wrap2]) "wrappers do not match."
                      guardMsg (exprAlphaEq unwrap unwrap1) "unwrappers do not match."
                      whenJust (verifyWWAss wrap unwrap f) mAss
                      mkFix f

    wrongFixBody :: String
    wrongFixBody = "body of fix does not have the form Lam b (App unwrap (App f (App wrap (Var b))))"

-- | For any @f :: A -> A@, and given @wrap :: B -> A@ and @unwrap :: A -> B@ as arguments, then
--   @fix A f@  \<==\>  @wrap (fix B (\\ b -> unwrap (f (wrap b))))@
workerWrapperFac :: Maybe WWAssumption -> CoreString -> CoreString -> BiRewriteH CoreExpr
workerWrapperFac mAss = parse2beforeBiR (workerWrapperFacBR mAss)

--------------------------------------------------------------------------------------------------

-- | Given @wrap :: B -> A@, @unwrap :: A -> B@ and @work :: B@ as arguments, then
--   @unwrap (wrap work)@  \<==\>  @work@
workerWrapperFusionBR :: BiRewriteH CoreExpr
workerWrapperFusionBR =
    beforeBiR (prefixFailMsg "worker/wrapper fusion failed: " $
               withPatFailMsg "malformed WW Fusion rule." $
               do Def w (App unwrap (App _f (App wrap (Var w')))) <- constT (lookupDef workLabel)
                  guardMsg (w == w') "malformed WW Fusion rule."
                  return (wrap,unwrap,Var w)
              )
              (\ (wrap,unwrap,work) -> bidirectional (fusL wrap unwrap work) (fusR wrap unwrap work))
  where
    fusL :: CoreExpr -> CoreExpr -> CoreExpr -> RewriteH CoreExpr
    fusL wrap unwrap work =
           prefixFailMsg "worker/wrapper fusion failed: " $
           withPatFailMsg (wrongExprForm "unwrap (wrap work)") $
           do App unwrap' (App wrap' work') <- idR
              guardMsg (exprAlphaEq wrap wrap') "wrapper does not match."
              guardMsg (exprAlphaEq unwrap unwrap') "unwrapper does not match."
              guardMsg (exprAlphaEq work work') "worker does not match."
              return work

    fusR :: CoreExpr -> CoreExpr -> CoreExpr -> RewriteH CoreExpr
    fusR wrap unwrap work =
           prefixFailMsg "(reverse) worker/wrapper fusion failed: " $
           do work' <- idR
              guardMsg (exprAlphaEq work work') "worker does not match."
              return $ App unwrap (App wrap work)


-- | Given @wrap :: B -> A@, @unwrap :: A -> B@ and @work :: B@ as arguments, then
--   @unwrap (wrap work)@  \<==\>  @work@
workerWrapperFusion :: BiRewriteH CoreExpr
workerWrapperFusion = workerWrapperFusionBR

--------------------------------------------------------------------------------------------------

-- | Save the recursive definition of work in the stash, so that we can later verify uses of 'workerWrapperFusionBR'.
--   Must be applied to a definition of the form: @work = unwrap (f (wrap work))@
--   Note that this is performed automatically as part of 'workerWrapperSplitR'.
workerWrapperGenerateFusionR :: Maybe WWAssumption -> RewriteH Core
workerWrapperGenerateFusionR mAss =
    prefixFailMsg "generate WW fusion failed: " $
    withPatFailMsg wrongForm $
    do Def w (App unwrap (App f (App wrap (Var w')))) <- projectT
       guardMsg (w == w') wrongForm
       whenJust (verifyWWAss wrap unwrap f) mAss
       rememberR workLabel
  where
    wrongForm = "definition does not have the form: work = unwrap (f (wrap work))"

--------------------------------------------------------------------------------------------------

-- | \\ wrap unwrap ->  (@prog = expr@  ==>  @prog = let f = \\ prog -> expr in let work = unwrap (f (wrap work)) in wrap work)@
workerWrapperSplitR :: Maybe WWAssumption -> CoreExpr -> CoreExpr -> RewriteH CoreDef
workerWrapperSplitR mAss wrap unwrap =
  let work = TH.mkName "work"
      fx   = TH.mkName "fix"
   in
      fixIntro
      >>> defAllR idR ( appAllR idR (letIntroR "f")
                        >>> letFloatArgR
                        >>> letAllR idR ( forewardT (workerWrapperFacBR mAss wrap unwrap)
                                          >>> appAllR idR ( unfoldNameR fx
                                                            >>> alphaLetWith [work]
                                                            >>> letRecAllR (\ _ -> defAllR idR (betaReduceR >>> letSubstR)
                                                                                   >>> extractR (workerWrapperGenerateFusionR mAss)
                                                                           )
                                                                           idR
                                                          )
                                          >>> letFloatArgR
                                        )
                      )

-- | \\ wrap unwrap ->  (@prog = expr@  ==>  @prog = let f = \\ prog -> expr in let work = unwrap (f (wrap work)) in wrap work)@
workerWrapperSplit :: Maybe WWAssumption -> CoreString -> CoreString -> RewriteH CoreDef
workerWrapperSplit mAss wrapS unwrapS = (parseCoreExprT wrapS &&& parseCoreExprT unwrapS) >>= uncurry (workerWrapperSplitR mAss)

-- | As 'workerWrapperSplit' but performs the static-argument transformation for @n@ type paramaters first, providing these types as arguments to all calls of wrap and unwrap.
--   This is useful if the expression, and wrap and unwrap, all have a @forall@ type.
workerWrapperSplitParam :: Int -> Maybe WWAssumption -> CoreString -> CoreString -> RewriteH CoreDef
workerWrapperSplitParam 0 = workerWrapperSplit
workerWrapperSplitParam n = \ mAss wrapS unwrapS ->
                            prefixFailMsg "worker/wrapper split (forall variant) failed: " $
                            do guardMsg (n == 1) "currently only supports 1 type paramater."
                               withPatFailMsg "right-hand-side of definition does not have the form: Lam t e" $
                                 do Def _ (Lam t _) <- idR
                                    guardMsg (isTyVar t) "first argument is not a type."
                                    let splitAtDefR :: RewriteH Core
                                        splitAtDefR = do p <- considerConstructT Definition
                                                         localPathR p $ promoteR $ do wrap   <- parseCoreExprT wrapS
                                                                                      unwrap <- parseCoreExprT unwrapS
                                                                                      let ty = Type (TyVarTy t)
                                                                                      workerWrapperSplitR mAss (App wrap ty) (App unwrap ty)
                                    staticArgR >>> extractR splitAtDefR

--------------------------------------------------------------------------------------------------

-- | Convert a proof of WW Assumption A into a proof of WW Assumption B.
wwAssAimpliesAssB :: RewriteH CoreExpr -> RewriteH CoreExpr
wwAssAimpliesAssB = id

-- | Convert a proof of WW Assumption B into a proof of WW Assumption C.
wwAssBimpliesAssC :: RewriteH CoreExpr -> RewriteH CoreExpr
wwAssBimpliesAssC assB = appAllR idR (lamAllR idR assB >>> etaReduceR)

-- | Convert a proof of WW Assumption A into a proof of WW Assumption C.
wwAssAimpliesAssC :: RewriteH CoreExpr -> RewriteH CoreExpr
wwAssAimpliesAssC =  wwAssBimpliesAssC . wwAssAimpliesAssB

--------------------------------------------------------------------------------------------------

-- | @wrap (unwrap a)@  \<==\>  @a@
wwAssA :: Maybe (RewriteH CoreExpr) -- ^ WW Assumption A
       -> CoreExpr                  -- ^ wrap
       -> CoreExpr                  -- ^ unwrap
       -> BiRewriteH CoreExpr
wwAssA mr wrap unwrap = beforeBiR (do whenJust (verifyAssA wrap unwrap) mr
                                      wrapUnwrapTypes wrap unwrap
                                  )
                                  (\ (tyA,_) -> bidirectional wwAL (wwAR tyA))
  where
    wwAL :: RewriteH CoreExpr
    wwAL = withPatFailMsg (wrongExprForm "App wrap (App unwrap x)") $
           do App wrap' (App unwrap' x) <- idR
              guardMsg (exprAlphaEq wrap wrap')     "given wrapper does not match wrapper in expression."
              guardMsg (exprAlphaEq unwrap unwrap') "given unwrapper does not match unwrapper in expression."
              return x

    wwAR :: Type -> RewriteH CoreExpr
    wwAR tyA = do x <- idR
                  guardMsg (exprType x `eqType` tyA) "type of expression does not match types of wrap/unwrap."
                  return $ App wrap (App unwrap x)

-- | @wrap (unwrap a)@  \<==\>  @a@
wwA :: Maybe (RewriteH CoreExpr) -- ^ WW Assumption A
    -> CoreString                -- ^ wrap
    -> CoreString                -- ^ unwrap
    -> BiRewriteH CoreExpr
wwA mr = parse2beforeBiR (wwAssA mr)

-- | @wrap (unwrap (f a))@  \<==\>  @f a@
wwAssB :: Maybe (RewriteH CoreExpr) -- ^ WW Assumption B
       -> CoreExpr                  -- ^ wrap
       -> CoreExpr                  -- ^ unwrap
       -> CoreExpr                  -- ^ f
       -> BiRewriteH CoreExpr
wwAssB mr wrap unwrap f = beforeBiR (whenJust (verifyAssB wrap unwrap f) mr)
                                    (\ () -> bidirectional wwBL wwBR)
  where
    assA :: BiRewriteH CoreExpr
    assA = wwAssA Nothing wrap unwrap

    wwBL :: RewriteH CoreExpr
    wwBL = withPatFailMsg (wrongExprForm "App wrap (App unwrap (App f a))") $
           do App _ (App _ (App f' _)) <- idR
              guardMsg (exprAlphaEq f f') "given body function does not match expression."
              forewardT assA

    wwBR :: RewriteH CoreExpr
    wwBR = withPatFailMsg (wrongExprForm "App f a") $
           do App f' _ <- idR
              guardMsg (exprAlphaEq f f') "given body function does not match expression."
              backwardT assA

-- | @wrap (unwrap (f a))@  \<==\>  @f a@
wwB :: Maybe (RewriteH CoreExpr) -- ^ WW Assumption B
    -> CoreString                -- ^ wrap
    -> CoreString                -- ^ unwrap
    -> CoreString                -- ^ f
    -> BiRewriteH CoreExpr
wwB mr = parse3beforeBiR (wwAssB mr)

-- | @fix A (\ a -> wrap (unwrap (f a)))@  \<==\>  @fix A f@
wwAssC :: Maybe (RewriteH CoreExpr) -- ^ WW Assumption C
       -> CoreExpr                  -- ^ wrap
       -> CoreExpr                  -- ^ unwrap
       -> CoreExpr                  -- ^ f
       -> BiRewriteH CoreExpr
wwAssC mr wrap unwrap f = beforeBiR (do _ <- isFixExpr
                                        whenJust (verifyAssC wrap unwrap f) mr
                                    )
                                    (\ () -> bidirectional wwCL wwCR)
  where
    assB :: BiRewriteH CoreExpr
    assB = wwAssB Nothing wrap unwrap f

    wwCL :: RewriteH CoreExpr
    wwCL = wwAssBimpliesAssC (forewardT assB)

    wwCR :: RewriteH CoreExpr
    wwCR = appAllR idR (etaExpandR "a" >>> lamAllR idR (backwardT assB))

-- | @fix A (\ a -> wrap (unwrap (f a)))@  \<==\>  @fix A f@
wwC :: Maybe (RewriteH CoreExpr) -- ^ WW Assumption C
    -> CoreString                -- ^ wrap
    -> CoreString                -- ^ unwrap
    -> CoreString                -- ^ f
    -> BiRewriteH CoreExpr
wwC mr = parse3beforeBiR (wwAssC mr)

--------------------------------------------------------------------------------------------------

verifyWWAss :: CoreExpr        -- ^ wrap
            -> CoreExpr        -- ^ unwrap
            -> CoreExpr        -- ^ f
            -> WWAssumption
            -> TranslateH x ()
verifyWWAss wrap unwrap f (WWAssumption tag ass) =
    case tag of
      A -> verifyAssA wrap unwrap ass
      B -> verifyAssB wrap unwrap f ass
      C -> verifyAssC wrap unwrap f ass

verifyAssA :: CoreExpr          -- ^ wrap
           -> CoreExpr          -- ^ unwrap
           -> RewriteH CoreExpr -- ^ WW Assumption A
           -> TranslateH x ()
verifyAssA wrap unwrap assA =
  prefixFailMsg ("verification of worker/wrapper Assumption A failed: ") $
  do (tyA,_) <- wrapUnwrapTypes wrap unwrap
     a       <- constT (newIdH "a" tyA)
     let lhs = App wrap (App unwrap (Var a))
         rhs = Var a
     verifyEqualityProofT lhs rhs assA

verifyAssB :: CoreExpr          -- ^ wrap
           -> CoreExpr          -- ^ unwrap
           -> CoreExpr          -- ^ f
           -> RewriteH CoreExpr -- ^ WW Assumption B
           -> TranslateH x ()
verifyAssB wrap unwrap f assB =
  prefixFailMsg ("verification of worker/wrapper assumption B failed: ") $
  do (tyA,_) <- wrapUnwrapTypes wrap unwrap
     a      <- constT (newIdH "a" tyA)
     let lhs = App wrap (App unwrap (App f (Var a)))
         rhs = App f (Var a)
     verifyEqualityProofT lhs rhs assB

verifyAssC :: CoreExpr          -- ^ wrap
           -> CoreExpr          -- ^ unwrap
           -> CoreExpr          -- ^ f
           -> RewriteH CoreExpr -- ^ WW Assumption C
           -> TranslateH a ()
verifyAssC wrap unwrap f assC =
  prefixFailMsg ("verification of worker/wrapper assumption C failed: ") $
  do (tyA,_) <- wrapUnwrapTypes wrap unwrap
     a       <- constT (newIdH "a" tyA)
     rhs     <- mkFix f
     lhs     <- mkFix (Lam a (App wrap (App unwrap (App f (Var a)))))
     verifyEqualityProofT lhs rhs assC

--------------------------------------------------------------------------------------------------

wrapUnwrapTypes :: MonadCatch m => CoreExpr -> CoreExpr -> m (Type,Type)
wrapUnwrapTypes wrap unwrap = setFailMsg "given expressions have the wrong types to form a valid wrap/unwrap pair." $
                              funsWithInverseTypes unwrap wrap

--------------------------------------------------------------------------------------------------
