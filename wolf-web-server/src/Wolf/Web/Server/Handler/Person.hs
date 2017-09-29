{-# LANGUAGE TemplateHaskell #-}

module Wolf.Web.Server.Handler.Person where

import Import

import Data.Time

import Yesod

import Wolf.Data
import Wolf.Data.Time

import Wolf.Web.Server.Foundation

getPersonR :: PersonUuid -> Handler Html
getPersonR uuid = do
    (mpe, ix, ns) <-
        runData $ do
            mpe <- getPersonEntry uuid
            ix <- getIndexWithDefault
            ns <- getPersonNotes uuid
            pure (mpe, ix, ns)
    now <- liftIO getCurrentTime
    let malias = reverseIndexLookupSingleAlias uuid ix
    defaultLayout $ withNavBar $(widgetFile "person")
