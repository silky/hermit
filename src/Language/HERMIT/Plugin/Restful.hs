{-# LANGUAGE PatternGuards, DataKinds, ScopedTypeVariables, DeriveDataTypeable,
             OverloadedStrings, KindSignatures, GADTs, TypeFamilies #-}

module Language.HERMIT.Plugin.Restful (passes) where

import Control.Applicative
import Control.Monad
import Control.Monad.IO.Class (liftIO)

import Data.Aeson
import Data.Default
import Data.Dynamic
import Data.List hiding (delete)
import qualified Data.Map as M
import qualified Data.Text.Lazy as T

-- The Prelude version of catch has been deprecated.
import Prelude hiding (catch)
import Control.Exception hiding (catch)

import Language.HERMIT.Dictionary
import Language.HERMIT.HermitExpr
import Language.HERMIT.Interp
import Language.HERMIT.Kernel
import Language.HERMIT.Plugin.Common
import Language.HERMIT.PrettyPrinter.JSON

import Network.HTTP.Types
import Paths_hermit
import Web.Scotty as S

passes :: [NamedPass]
passes = [("w", restful)]

restful :: HermitPass
restful opts modGuts = hermitKernel (webapp dict indexfile) modGuts
    where dict = dictionary [] modGuts
          indexfile = head [ o | o <- opts, ".html" `isSuffixOf` o ]

webapp :: M.Map String [Dynamic] -> FilePath -> Kernel -> AST -> IO ()
webapp dict indexfile kernel _initAst = do
    dataDir <- getDataDir

    let respondWith :: AST -> ActionM ()
        respondWith ast@(AST i) = do
            val <- liftIO $ queryK kernel ast (corePrettyH def)
            S.json $ object ["ast" .= i, "code" .= val]

    scotty 3000 $ do
        get "/index" $ file indexfile
        get "/jquery.js" $ file $ dataDir ++ "/javascript/jquery.js"
        get "/jquery-json.js" $ file $ dataDir ++ "/javascript/jquery-json.js"

        post "/:ast" $ do
            ast <- param "ast"
            liftIO $ quitK kernel (AST ast)

        put "/:ast" $ do
            ast <- param "ast"
            Apply rr <- parseCommand dict =<< jsonData
            ast' <- liftIO ((liftM Right $ applyK kernel (AST ast) rr) `catch` (return . Left))
            either (raise . T.pack) respondWith ast'

        post "/:ast/query" $ do
            ast <- param "ast"
            Query q <- parseCommand dict =<< jsonData
            res <- liftIO ((liftM Right $ queryK kernel (AST ast) q) `catch` (return . Left))
            either (raise . T.pack) (S.text . T.pack . show) res

        delete "/:ast" $ do
            ast <- param "ast"
            liftIO $ deleteK kernel $ AST ast

        get "/" $ do
            l <- liftIO $ listK kernel
            S.json [ i | AST i <- l ]

        addroute OPTIONS "/" $ do
            text "help"


-- rather than abuse the command line parser here,
-- need to assign each command a unique id, and call with those
parseCommand :: M.Map String [Dynamic] -> ExprH -> ActionM KernelCommand
parseCommand dict expr = either (raise . T.pack) return $ interpExprH dict interpKernelCommand expr

instance FromJSON ExprH where
   parseJSON (Object o) = do
        con :: String <- o .: "type"
        case con of
            "Src" -> SrcName <$> o .: "value"
            "Cmd" -> CmdName <$> o .: "value"
            "Str" -> StrName <$> o .: "value"
            "App" -> AppH <$> o .: "lhs" <*> o .: "rhs"

   parseJSON _ = mzero

catch :: IO a -> (String -> IO a) -> IO a
catch = catchJust (\ (err :: IOException) -> return (show err))
