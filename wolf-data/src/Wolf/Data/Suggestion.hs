{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}

module Wolf.Data.Suggestion
    ( Suggestion(..)
    , SuggestionType
    , aliasSuggestionType
    , AliasSuggestion(..)
    , entrySuggestionType
    , EntrySuggestion(..)
    , sameEntrySuggestionData
    , sameEntrySuggestion
    , hashSuggestion
    , SuggestionIndex
    , suggestionIndexMap
    , readUnusedSuggestions
    , writeUnusedSuggestions
    , addUnusedSuggestions
    , addUnusedSuggestion
    , readUsedSuggestions
    , writeUsedSuggestions
    , recordUsedSuggestions
    , recordUsedSuggestion
    ) where

import Import

import qualified Data.Map as M
import qualified Data.Set as S

import Wolf.Data.JSONUtils
import Wolf.Data.Path
import Wolf.Data.Types

import Wolf.Data.Suggestion.Types

suggestionsDir :: MonadReader DataSettings m => m (Path Abs Dir)
suggestionsDir = (</> $(mkRelDir "suggestions")) <$> wolfDir

aliasSuggestionType :: SuggestionType AliasSuggestion
aliasSuggestionType = SuggestionType $(mkRelDir "alias")

entrySuggestionType :: SuggestionType EntrySuggestion
entrySuggestionType = SuggestionType $(mkRelDir "entry")

suggestionTypeDir ::
       MonadReader DataSettings m => SuggestionType a -> m (Path Abs Dir)
suggestionTypeDir (SuggestionType d) = (</> d) <$> suggestionsDir

unusedSuggestionsIndexFile ::
       MonadReader DataSettings m => SuggestionType a -> m (Path Abs File)
unusedSuggestionsIndexFile typ =
    (</> $(mkRelFile "unused.json")) <$> suggestionTypeDir typ

usedSuggestionsIndexFile ::
       MonadReader DataSettings m => SuggestionType a -> m (Path Abs File)
usedSuggestionsIndexFile typ =
    (</> $(mkRelFile "used.json")) <$> suggestionTypeDir typ

hashSuggestion :: Hashable a => Suggestion a -> SuggestionHash a
hashSuggestion = SuggestionHash . fromIntegral . hash . suggestionData

emptySuggestionIndex :: SuggestionIndex a
emptySuggestionIndex = SuggestionIndex {suggestionIndexMap = M.empty}

suggestionFilePath ::
       (MonadIO m, MonadReader DataSettings m)
    => SuggestionType a
    -> SuggestionUuid
    -> m (Path Abs File)
suggestionFilePath typ u = do
    d <- suggestionTypeDir typ
    resolveFile d $ uuidString u

readSuggestion ::
       (MonadIO m, MonadReader DataSettings m, FromJSON a, Hashable a)
    => SuggestionType a
    -> SuggestionUuid
    -> SuggestionHash a
    -> m (Maybe (Suggestion a))
readSuggestion typ u h = do
    f <- suggestionFilePath typ u
    ms <- readJSONWithMaybe f
    pure $
        (ms >>=) $ \s ->
            if hashSuggestion s == h
                then Just s
                else Nothing

writeSuggestion ::
       (MonadIO m, MonadReader DataSettings m, ToJSON a)
    => SuggestionType a
    -> SuggestionUuid
    -> Suggestion a
    -> m ()
writeSuggestion typ u s = do
    f <- suggestionFilePath typ u
    writeJSON f s

readUnusedSuggestionIndex ::
       (MonadIO m, MonadReader DataSettings m)
    => SuggestionType a
    -> m (SuggestionIndex a)
readUnusedSuggestionIndex typ =
    unusedSuggestionsIndexFile typ >>= readJSONWithDefault emptySuggestionIndex

readUnusedSuggestions ::
       (MonadIO m, MonadReader DataSettings m, FromJSON a, Ord a, Hashable a)
    => SuggestionType a
    -> m (Set (Suggestion a))
readUnusedSuggestions typ = do
    (SuggestionIndex ix) <- readUnusedSuggestionIndex typ
    ix_ <- M.traverseWithKey (flip $ readSuggestion typ) ix
    pure $ S.fromList . catMaybes . M.elems $ ix_

writeUnusedSuggestionIndex ::
       (MonadIO m, MonadReader DataSettings m)
    => SuggestionType a
    -> SuggestionIndex a
    -> m ()
writeUnusedSuggestionIndex typ ix = do
    f <- unusedSuggestionsIndexFile typ
    writeJSON f ix

writeUnusedSuggestions ::
       (MonadIO m, MonadReader DataSettings m, ToJSON a, Hashable a)
    => SuggestionType a
    -> Set (Suggestion a)
    -> m ()
writeUnusedSuggestions typ ess = do
    tups <-
        forM (S.toList ess) $ \s ->
            (,) s <$> ((,) (hashSuggestion s) <$> nextRandomUUID)
    let ix = SuggestionIndex $ M.fromList $ map snd tups
    writeUnusedSuggestionIndex typ ix
    forM_ tups $ \(s, (_, u)) -> writeSuggestion typ u s

addUnusedSuggestions ::
       forall a m.
       ( MonadIO m
       , MonadReader DataSettings m
       , Eq a
       , FromJSON a
       , ToJSON a
       , Hashable a
       )
    => SuggestionType a
    -> Set (Suggestion a)
    -> m ()
addUnusedSuggestions typ newSugs = do
    (SuggestionIndex ix) <- readUnusedSuggestionIndex typ
    newIx <- foldM go ix newSugs
    writeUnusedSuggestionIndex typ $ SuggestionIndex newIx
  where
    go :: Map (SuggestionHash a) SuggestionUuid
       -> Suggestion a
       -> m (Map (SuggestionHash a) SuggestionUuid)
    go m s =
        let h = hashSuggestion s
        in case M.lookup h m of
               Nothing -> do
                   u <- nextRandomUUID
                   let m_ = M.insert h u m
                   writeSuggestion typ u s
                   pure m_
               Just _ -> pure m

addUnusedSuggestion ::
       ( MonadIO m
       , MonadReader DataSettings m
       , Eq a
       , FromJSON a
       , ToJSON a
       , Hashable a
       )
    => SuggestionType a
    -> Suggestion a
    -> m ()
addUnusedSuggestion typ s = addUnusedSuggestions typ $ S.singleton s

readUsedSuggestionIndex ::
       (MonadIO m, MonadReader DataSettings m)
    => SuggestionType a
    -> m (SuggestionIndex a)
readUsedSuggestionIndex typ =
    usedSuggestionsIndexFile typ >>= readJSONWithDefault emptySuggestionIndex

readUsedSuggestions ::
       (MonadIO m, MonadReader DataSettings m, FromJSON a, Ord a, Hashable a)
    => SuggestionType a
    -> m (Set (Suggestion a))
readUsedSuggestions typ = do
    (SuggestionIndex ix) <- readUsedSuggestionIndex typ
    ix_ <- M.traverseWithKey (flip $ readSuggestion typ) ix
    pure $ S.fromList . catMaybes . M.elems $ ix_

writeUsedSuggestionIndex ::
       (MonadIO m, MonadReader DataSettings m)
    => SuggestionType a
    -> SuggestionIndex a
    -> m ()
writeUsedSuggestionIndex typ ix = do
    f <- usedSuggestionsIndexFile typ
    writeJSON f ix

writeUsedSuggestions ::
       (MonadIO m, MonadReader DataSettings m, ToJSON a, Hashable a)
    => SuggestionType a
    -> Set (Suggestion a)
    -> m ()
writeUsedSuggestions typ ess = do
    tups <-
        forM (S.toList ess) $ \s ->
            (,) s <$> ((,) (hashSuggestion s) <$> nextRandomUUID)
    let ix = SuggestionIndex $ M.fromList $ map snd tups
    writeUsedSuggestionIndex typ ix
    forM_ tups $ \(s, (_, u)) -> writeSuggestion typ u s

recordUsedSuggestions ::
       forall a m.
       ( MonadIO m
       , MonadReader DataSettings m
       , Eq a
       , ToJSON a
       , FromJSON a
       , Hashable a
       )
    => SuggestionType a
    -> Set (Suggestion a)
    -> m ()
recordUsedSuggestions typ usedSugs = do
    (SuggestionIndex uusi) <- readUnusedSuggestionIndex typ
    (SuggestionIndex usi) <- readUsedSuggestionIndex typ
    let (uusi', usi') = foldl' go (uusi, usi) usedSugs
    writeUnusedSuggestionIndex typ $ SuggestionIndex uusi'
    writeUsedSuggestionIndex typ $ SuggestionIndex usi'
  where
    go :: ( Map (SuggestionHash a) SuggestionUuid
          , Map (SuggestionHash a) SuggestionUuid)
       -> Suggestion a
       -> ( Map (SuggestionHash a) SuggestionUuid
          , Map (SuggestionHash a) SuggestionUuid)
    go t@(uusi, usi) s =
        let h = hashSuggestion s
        in case M.lookup h uusi of
               Nothing -> t -- Wasn't unused, can't record that it's being used.
               Just uuid ->
                   case M.lookup h usi of
                       Just uuid' ->
                           if uuid == uuid'
                               then (M.delete h uusi, usi) -- Wasn't deleted yet, let's do it now
                               else ( M.delete h uusi
                                    , M.insert h uuid usi -- Wasn't deleted yet, AND had the wrong uuid.
                                     )
                       Nothing -> (M.delete h uusi, M.insert h uuid usi)

recordUsedSuggestion ::
       forall a m.
       ( MonadIO m
       , MonadReader DataSettings m
       , Eq a
       , ToJSON a
       , FromJSON a
       , Hashable a
       )
    => SuggestionType a
    -> Suggestion a
    -> m ()
recordUsedSuggestion typ s = recordUsedSuggestions typ $ S.singleton s
