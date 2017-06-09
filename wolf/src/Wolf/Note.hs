module Wolf.Note where

import Import

import qualified Data.Text.IO as T
import Data.Time

import Wolf.Editor
import Wolf.Index
import Wolf.JSONUtils
import Wolf.NoteIndex
import Wolf.Path
import Wolf.Types

note
    :: MonadIO m
    => String -> m ()
note person = do
    origIndex <- getIndex
    (personUuid, index) <- lookupOrCreateNewPerson person origIndex
    origNoteIndex <- getNoteIndex personUuid
    (noteUuid, noteIndex) <- createNewNote personUuid origNoteIndex
    tnf <- tmpPersonNoteFile personUuid noteUuid
    editingResult <- startEditorOn tnf
    case editingResult of
        EditingFailure reason ->
            liftIO $
            putStrLn $
            unwords
                ["ERROR: failed to edit the note file:", reason, ",not saving."]
        EditingSuccess -> do
            now <- liftIO getCurrentTime
            contents <- liftIO $ T.readFile $ toFilePath tnf
            let personNote =
                    PersonNote
                    {personNoteContents = contents, personNoteTimestamp = now}
            nf <- personNoteFile personUuid noteUuid
            writeJSON nf personNote
            putIndex index
            putNoteIndex personUuid noteIndex
