{-# LANGUAGE KindSignatures, GADTs, FlexibleContexts, TypeFamilies, DeriveDataTypeable, GeneralizedNewtypeDeriving #-}

module HERMIT.Shell.Types where

import Control.Concurrent.STM
import Control.Monad.State
import Control.Monad.Error

import Data.Dynamic
import qualified Data.Map as M

import HERMIT.Context
import HERMIT.Kure
import HERMIT.External
import qualified HERMIT.GHC as GHC
import HERMIT.Kernel.Scoped
import HERMIT.Parser
import HERMIT.PrettyPrinter.Common

import System.IO

----------------------------------------------------------------------------------

-- | There are four types of commands.
data ShellCommand =  KernelEffect KernelEffect -- ^ Command that modifies the state of the (scoped) kernel.
                  |  ShellEffect  ShellEffect  -- ^ Command that modifies the state of the shell.
                  |  QueryFun     QueryFun     -- ^ Command that queries the AST with a Translate (read only).
                  |  MetaCommand  MetaCommand  -- ^ Command that otherwise controls HERMIT (abort, resume, save, etc).

-- GADTs can't have docs on constructors. See Haddock ticket #43.
-- | KernelEffects are things that affect the state of the Kernel
--   - Apply a rewrite (giving a whole new lower-level AST).
--   - Change the current location using a computed path.
--   - Change the currect location using directions.
--   - Begin or end a scope.
--   - Delete an AST
--   - Run a precondition or other predicate that must not fail.
data KernelEffect :: * where
   Apply      :: (Injection GHC.ModGuts g, Walker HermitC g) => RewriteH g              -> KernelEffect
   Pathfinder :: (Injection GHC.ModGuts g, Walker HermitC g) => TranslateH g LocalPathH -> KernelEffect
   Direction  ::                                                Direction               -> KernelEffect
   BeginScope ::                                                                           KernelEffect
   EndScope   ::                                                                           KernelEffect
   Delete     ::                                                SAST                    -> KernelEffect
   CorrectnessCritera :: (Injection GHC.ModGuts g, Walker HermitC g) => TranslateH g () -> KernelEffect
   deriving Typeable

instance Extern KernelEffect where
   type Box KernelEffect = KernelEffect
   box i = i
   unbox i = i

data ShellEffect :: * where
   CLSModify :: (CommandLineState -> IO CommandLineState) -> ShellEffect
   deriving Typeable

data QueryFun :: * where
   QueryString   :: (Injection GHC.ModGuts g, Walker HermitC g)
                 => TranslateH g String                                   -> QueryFun
   QueryDocH     :: (PrettyC -> PrettyH CoreTC -> TranslateH CoreTC DocH) -> QueryFun
   Display       ::                                                          QueryFun
   Inquiry       :: (CommandLineState -> IO String)                       -> QueryFun
   deriving Typeable

message :: String -> QueryFun
message str = Inquiry (const $ return str)

instance Extern QueryFun where
   type Box QueryFun = QueryFun
   box i = i
   unbox i = i

type RewriteName = String

data MetaCommand
   = Resume
   | Abort
   | Continue -- exit the shell, but don't abort/resume
   | Diff SAST SAST
   | Dump String String Int
   | LoadFile ScriptName FilePath  -- load a file on top of the current node
   | SaveFile FilePath
   | ScriptToRewrite RewriteName ScriptName
   | DefineScript ScriptName String
   | RunScript ScriptName
   | SaveScript FilePath ScriptName
   | SeqMeta [MetaCommand]
   deriving Typeable

-- | A composite meta-command for running a loaded script immediately.
--   The script is given the same name as the filepath.
loadAndRun :: FilePath -> MetaCommand
loadAndRun fp = SeqMeta [LoadFile fp fp, RunScript fp]

instance Extern MetaCommand where
    type Box MetaCommand = MetaCommand
    box i = i
    unbox i = i

data VersionCmd = Back                  -- back (up) the derivation tree
                | Step                  -- down one step; assumes only one choice
                | Goto Int              -- goto a specific node, if possible
                | GotoTag String        -- goto a specific named tag
                | AddTag String         -- add a tag
        deriving Show

instance Extern ShellEffect where
    type Box ShellEffect = ShellEffect
    box i = i
    unbox i = i

----------------------------------------------------------------------------------

data CLException = CLAbort
                 | CLResume SAST
                 | CLContinue CommandLineState
                 | CLError String

instance Error CLException where
    strMsg = CLError

newtype CLM m a = CLM { unCLM :: ErrorT CLException (StateT CommandLineState m) a }
    deriving (MonadIO, MonadError CLException, MonadState CommandLineState)

-- | Our own custom instance of Monad for CLM m so we don't have to depend on
-- newtype deriving to do the right thing for fail.
instance Monad m => Monad (CLM m) where
    return = CLM . return
    (CLM m) >>= k = CLM (m >>= unCLM . k)
    fail = CLM . throwError . CLError

abort :: Monad m => CLM m ()
abort = throwError CLAbort

resume :: Monad m => SAST -> CLM m ()
resume = throwError . CLResume

continue :: Monad m => CommandLineState -> CLM m ()
continue = throwError . CLContinue

instance MonadTrans CLM where
    lift = CLM . lift . lift

instance Monad m => MonadCatch (CLM m) where
    -- law: fail msg `catchM` f == f msg
    -- catchM :: m a -> (String -> m a) -> m a
    catchM m f = do
        st <- get
        (r,st') <- lift $ runCLM st m
        case r of
            Left err -> case err of
                            CLError msg -> f msg
                            other -> throwError other -- rethrow abort/resume
            Right v  -> put st' >> return v

runCLM :: CommandLineState -> CLM m a -> m (Either CLException a, CommandLineState)
runCLM s = flip runStateT s . runErrorT . unCLM

-- TODO: Come up with names for these, and/or better characterise these abstractions.
iokm2clm' :: MonadIO m => String -> (a -> CLM m b) -> IO (KureM a) -> CLM m b
iokm2clm' msg ret m = liftIO m >>= runKureM ret (throwError . CLError . (msg ++))

iokm2clm :: MonadIO m => String -> IO (KureM a) -> CLM m a
iokm2clm msg = iokm2clm' msg return

iokm2clm'' :: MonadIO m => IO (KureM a) -> CLM m a
iokm2clm'' = iokm2clm ""

data VersionStore = VersionStore
    { vs_graph       :: [(SAST,ExprH,SAST)]
    , vs_tags        :: [(String,SAST)]
    }

newSAST :: ExprH -> SAST -> CommandLineState -> CommandLineState
newSAST expr sast st = st { cl_cursor = sast
                          , cl_version = (cl_version st) { vs_graph = (cl_cursor st, expr, sast) : vs_graph (cl_version st) }
                          }

-- Session-local issues; things that are never saved.
data CommandLineState = CommandLineState
    { cl_cursor         :: SAST                                     -- ^ the current AST
    , cl_pretty         :: PrettyH CoreTC                           -- ^ which pretty printer to use
    , cl_pretty_opts    :: PrettyOptions                            -- ^ the options for the pretty printer
    , cl_render         :: Handle -> PrettyOptions -> Either String DocH -> IO () -- ^ the way of outputing to the screen
    , cl_height         :: Int                                      -- ^ console height, in lines
    , cl_nav            :: Bool                                     -- ^ keyboard input the nav panel
    , cl_running_script :: Bool                                     -- ^ if running a script
    , cl_tick           :: TVar (M.Map String Int)                  -- ^ the list of ticked messages
    , cl_corelint       :: Bool                                     -- ^ if true, run Core Lint on module after each rewrite
    , cl_diffonly       :: Bool                                     -- ^ if true, show diffs rather than pp full code
    , cl_failhard       :: Bool                                     -- ^ if true, abort on *any* failure
    , cl_window         :: PathH                                    -- ^ path to beginning of window, always a prefix of focus path in kernel
    -- these four should be in a reader
    , cl_dict           :: Dictionary
    , cl_scripts        :: [(ScriptName,Script)]
    , cl_kernel         :: ScopedKernel
    , cl_initSAST       :: SAST
    -- and the version store
    , cl_version        :: VersionStore
    }

type ScriptName = String
