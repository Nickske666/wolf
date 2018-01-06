{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}

module Wolf.Web.Server.Handler.People where

import Import

import qualified Data.Map as M
import Data.Map (Map)
import Data.Set (Set)
import qualified Data.Set as S
import qualified Data.Text as T

import Control.Monad.Reader

import Yesod
import Yesod.Auth

import Wolf.Data
import Wolf.Data.Baked

import Wolf.Web.Server.Foundation

getPeopleR :: Handler Html
getPeopleR = do
    void requireAuthId
    pcs <- runData getAllPeopleCards
    withNavBar $ do
        setTitle "Wolf People"
        $(widgetFile "people")

getAllPeopleCards :: ReaderT DataSettings IO WolfWidget
getAllPeopleCards = do
    pm <-
        do ix <- getIndexWithDefault
           M.traverseWithKey (\puuid as -> (,) as <$> getPersonEntry puuid) $
               reverseIndex ix
    pure $ peopleCards pm

peopleCards :: Map PersonUuid (Set Alias, Maybe PersonEntry) -> WolfWidget
peopleCards trips = do
    let pcs = map snd $ sortOn fst $ M.elems $ M.mapWithKey personCard trips
    $(widgetFile "people/items")

personCard :: PersonUuid -> (Set Alias, Maybe PersonEntry) -> (Text, WolfWidget)
personCard uuid (aliases, mpe) =
    let a =
            case S.toList aliases of
                [] -> "Unaliased person"
                (a_:_) -> a_
        displayName =
            fromMaybe (aliasText a) $ (fromEntry <$> mpe) >>= renderDisplayName
        mmet = metText <$> (mpe >>= fromEntry)
        mgender = mpe >>= fromEntry
    in (displayName, $(widgetFile "people/item"))

renderDisplayName :: Name -> Maybe Text
renderDisplayName Name {..} =
    case (nameFirst, nameLast) of
        (Nothing, Nothing) -> Nothing
        (Just fn, Nothing) ->
            Just $
            T.unwords $ fn : maybeToList ((("(" <>) . (<> ")")) <$> nameMiddle)
        (Nothing, Just ln) -> Just $ "Mr or Ms " <> ln
        (Just fn, Just ln) ->
            Just $ T.unwords $ [fn] ++ maybeToList nameMiddle ++ [ln]
