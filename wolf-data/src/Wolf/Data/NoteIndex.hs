{-# LANGUAGE FlexibleContexts #-}

module Wolf.Data.NoteIndex
    ( NoteIndex(..)
    , NoteUuid
    -- * Manipulating indices purely
    , addToNoteIndex
    , containsNoteUuid
    -- * Manipulate the global note index
    , getNoteIndex
    , putNoteIndex
    -- * Manipulate a person's note index
    , getPersonNoteIndex
    , putPersonNoteIndex
    -- ** Convenience functions for a person's notes
    , getNoteUuids
    , getNotes
    -- * Creating new notes, end-to-end
    , createNewNote
    , createNewNoteUuid
    ) where

import Import

import Wolf.Data.JSONUtils
import Wolf.Data.Note
import Wolf.Data.Path
import Wolf.Data.Types

-- | Add a note uuid to a note index
--
-- Nothing if the note uuid already existed in the index
addToNoteIndex :: NoteIndex -> NoteUuid -> Maybe NoteIndex
addToNoteIndex ni@(NoteIndex uuids) nuuid =
    if ni `containsNoteUuid` nuuid
        then Nothing
        else Just $ NoteIndex $ nuuid : uuids

-- | Check if a given note index contains a given note uuid
containsNoteUuid :: NoteIndex -> NoteUuid -> Bool
containsNoteUuid noteIndex noteUuid = noteUuid `elem` noteIndexList noteIndex

-- | Retrieve the global note index
getNoteIndex :: (MonadIO m, MonadReader DataSettings m) => m NoteIndex
getNoteIndex = noteIndexFile >>= readJSONWithDefault newNoteIndex

-- | Save the global note index
putNoteIndex :: (MonadIO m, MonadReader DataSettings m) => NoteIndex -> m ()
putNoteIndex noteIndex = do
    i <- noteIndexFile
    writeJSON i noteIndex

-- | Retrieve a person's note index
getPersonNoteIndex ::
       (MonadIO m, MonadReader DataSettings m) => PersonUuid -> m NoteIndex
getPersonNoteIndex personUuid =
    personNoteIndexFile personUuid >>= readJSONWithDefault newNoteIndex

-- | Save a person's note index
putPersonNoteIndex ::
       (MonadIO m, MonadReader DataSettings m)
    => PersonUuid
    -> NoteIndex
    -> m ()
putPersonNoteIndex personUuid noteIndex = do
    i <- personNoteIndexFile personUuid
    writeJSON i noteIndex

-- | Get all notes' uuid's for a given person
getNoteUuids ::
       (MonadIO m, MonadReader DataSettings m) => PersonUuid -> m [NoteUuid]
getNoteUuids personUuid = noteIndexList <$> getPersonNoteIndex personUuid

-- | Retrieve all notes for a given person
getNotes :: (MonadIO m, MonadReader DataSettings m) => PersonUuid -> m [Note]
getNotes personUuid = do
    nuuids <- getNoteUuids personUuid
    catMaybes <$> mapM readNote nuuids

createNewNote :: (MonadIO m, MonadReader DataSettings m) => Note -> m NoteUuid
createNewNote n = do
    gni <- getNoteIndex
    pniTups <-
        forM (noteRelevantPeople n) $ \personUuid ->
            (,) personUuid <$> getPersonNoteIndex personUuid
    go gni pniTups
  where
    go gni pniTups = do
        (newUuid, newGlobalIndex) <- createNewNoteUuid gni
        let mnis =
                forM pniTups $ \(personUuid, personNoteIndex) ->
                    (,) personUuid <$> addToNoteIndex personNoteIndex newUuid
        case mnis of
            Nothing -> go gni pniTups -- Try generating another uuid
            Just newPnis -> do
                putNoteIndex newGlobalIndex
                mapM_ (uncurry putPersonNoteIndex) newPnis
                writeNote newUuid n
                pure newUuid

-- | Create a new note in a note index.
-- The result is the new uuid and the new index
createNewNoteUuid ::
       MonadIO m
    => NoteIndex -- ^ The global note index
    -> m (NoteUuid, NoteIndex)
createNewNoteUuid noteIndex = do
    noteUuid <- nextRandomNoteUuid
    if noteIndex `containsNoteUuid` noteUuid
        then createNewNoteUuid noteIndex -- Just try again
        else pure
                 ( noteUuid
                 , noteIndex
                   {noteIndexList = sort $ noteUuid : noteIndexList noteIndex})
