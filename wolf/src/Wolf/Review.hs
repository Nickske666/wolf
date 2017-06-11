module Wolf.Review where

import Import

import qualified Data.Map as M
import qualified Data.Text as T
import System.Console.ANSI as ANSI

import Wolf.Index
import Wolf.NoteIndex
import Wolf.Report
import Wolf.Types

review :: IO ()
review = do
    index <- getIndex
    let tups = nubBy (\t1 t2 -> snd t1 == snd t2) $ M.toList $ indexMap index
    noteTups <-
        fmap concat $
        forM tups $ \(nn, personUuid) -> do
            notes <- getPersonNotes personUuid
            pure $ map ((,) nn) notes
    let entries = sortOn (personNoteTimestamp . snd) noteTups
    forM_ entries $ \(nickName, personNote) -> do
        print nickName
        print personNote
    let report =
            mconcat $
            flip map entries $ \(nickName, personNote) ->
                unlinesReport
                    [ colored [SetColor Foreground Dull Blue] $
                      unwords [nickName]
                    , stringReport $ T.unpack $ personNoteContents personNote
                    ]
    putStr $ renderReport report
