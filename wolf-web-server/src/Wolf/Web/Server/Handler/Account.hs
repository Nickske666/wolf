{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}

module Wolf.Web.Server.Handler.Account where

import Import

import qualified Data.Map as M

import Yesod
import Yesod.Auth

import Wolf.Data

import Wolf.Web.Server.Foundation

getAccountR :: Handler Html
getAccountR = do
    void requireAuthId
    -- FIXME: make the example independent of where this is run.
    withNavBar $ do
        setTitle "Wolf Account"
        $(widgetFile "account")
