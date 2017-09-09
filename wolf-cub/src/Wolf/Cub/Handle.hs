{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Wolf.Cub.Handle where

import Import

import Control.Monad.Reader

import qualified Data.Vector as V

import Brick.Main
import Brick.Types
import Brick.Widgets.List
import Graphics.Vty as V

import Wolf.Data

import Wolf.Cub.PropertyEditor
import Wolf.Cub.Types

makePersonList :: Index -> List ResourceName (Text, PersonUuid)
makePersonList i = list "person-list" (V.fromList $ indexTuples i) 1

handleEvent ::
       CubState
    -> BrickEvent ResourceName ()
    -> EventM ResourceName (Next CubState)
handleEvent state e =
    case cubStateShown state of
        CubShowPersonList pls -> handleEventShowPersonList state e pls
        CubShowPerson ps -> handleEventShowPerson state e ps
        CubEditPerson eps -> handleEditPerson state e eps

handleEventShowPersonList ::
       CubState
    -> BrickEvent ResourceName ()
    -> PersonListState
    -> EventM ResourceName (Next CubState)
handleEventShowPersonList state e pls@PersonListState {..} =
    case e of
        (VtyEvent ve) ->
            if personListStateShowHelp
                then let unhelp = setPersonListShowHelp state pls False
                     in case ve of
                            (EvKey V.KEsc []) -> unhelp
                            (EvKey (V.KChar 'q') []) -> unhelp
                            (EvKey (V.KChar 'h') []) -> unhelp
                            _ -> continue state
                else case ve of
                         (EvKey V.KEsc []) -> halt state
                         (EvKey (V.KChar 'q') []) -> halt state
                         (EvKey (V.KChar 'h') []) ->
                             setPersonListShowHelp state pls True
                         (EvKey V.KEnter []) -> do
                             let msel =
                                     listSelectedElement personListStatePeople
                             case msel of
                                 Nothing -> continue state
                                 Just (_, (_, personUuid)) ->
                                     showPerson state personUuid
                         _ -> do
                             nl <- handleListEvent ve personListStatePeople
                             let ns = pls {personListStatePeople = nl}
                             continue $
                                 state {cubStateShown = CubShowPersonList ns}
        _ -> continue state

setPersonListShowHelp ::
       CubState -> PersonListState -> Bool -> EventM n (Next CubState)
setPersonListShowHelp state pls b =
    continue
        state
        {cubStateShown = CubShowPersonList pls {personListStateShowHelp = b}}

handleEventShowPerson ::
       CubState
    -> BrickEvent ResourceName ()
    -> PersonState
    -> EventM ResourceName (Next CubState)
handleEventShowPerson state e ps@PersonState {..} =
    case e of
        (VtyEvent ve) ->
            if personStateShowHelp
                then let unhelp = setPersonShowHelp state ps False
                     in case ve of
                            (EvKey V.KEsc []) -> unhelp
                            (EvKey (V.KChar 'q') []) -> unhelp
                            (EvKey (V.KChar 'h') []) -> unhelp
                            _ -> continue state
                else let unpop = showPersonList state
                     in case ve of
                            (EvKey V.KEsc []) -> unpop
                            (EvKey (V.KChar 'q') []) -> unpop
                            (EvKey (V.KChar 'h') []) ->
                                setPersonShowHelp state ps True
                            (EvKey (V.KChar 'e') []) ->
                                editPerson state personStateUuid
                            _ -> do
                                nl <- handleListEvent ve personStateNotes
                                continue $
                                    state
                                    { cubStateShown =
                                          CubShowPerson $
                                          ps {personStateNotes = nl}
                                    }
        _ -> continue state

setPersonShowHelp :: CubState -> PersonState -> Bool -> EventM n (Next CubState)
setPersonShowHelp state ps b =
    continue $
    state {cubStateShown = CubShowPerson $ ps {personStateShowHelp = b}}

handleEditPerson ::
       CubState
    -> BrickEvent ResourceName ()
    -> EditPersonState
    -> EventM ResourceName (Next CubState)
handleEditPerson state e eps@EditPersonState {..} =
    case e of
        (VtyEvent ve) ->
            case ve of
                (EvKey V.KEsc []) -> unpop
                (EvKey (V.KChar 'q') []) -> unpop
                _ -> do
                    ne <-
                        handlePropertyEditorEvent
                            ve
                            editPersonStatePropertyEditor
                    continue $
                        state
                        { cubStateShown =
                              CubEditPerson $
                              eps {editPersonStatePropertyEditor = ne}
                        }
        _ -> continue state
  where
    unpop = do
        save
        showPerson state editPersonStateUuid
    save =
        liftIO $
        flip runReaderT (cubStateDataSettings state) $
        case propertyEditorCurrentValue editPersonStatePropertyEditor of
            Nothing -> pure () -- TODO delete the entry if it was deleted?
            Just pe -> putPersonEntry editPersonStateUuid pe

showPerson :: CubState -> PersonUuid -> EventM ResourceName (Next CubState)
showPerson state personUuid = do
    (mpe, ns) <-
        liftIO $
        flip runReaderT (cubStateDataSettings state) $ do
            mpe <- getPersonEntry personUuid
            nuuids <- getPersonNoteUuids personUuid
            ns <-
                fmap catMaybes $
                forM nuuids $ \uuid -> do
                    n <- readNote uuid
                    pure $ (,) uuid <$> n
            pure (mpe, ns)
    let nl = list "notes" (V.fromList ns) 1
    continue $
        state
        { cubStateShown =
              CubShowPerson
                  PersonState
                  { personStateUuid = personUuid
                  , personStateEntry = mpe
                  , personStateNotes = nl
                  , personStateShowHelp = False
                  }
        }

showPersonList :: CubState -> EventM n (Next CubState)
showPersonList state = do
    index <- runReaderT getIndexWithDefault $ cubStateDataSettings state
    continue $
        state
        { cubStateShown =
              CubShowPersonList
                  PersonListState
                  { personListStatePeople = makePersonList index
                  , personListStateShowHelp = False
                  }
        }

editPerson :: CubState -> PersonUuid -> EventM n (Next CubState)
editPerson state personUuid = do
    mpe <-
        liftIO $
        flip runReaderT (cubStateDataSettings state) $ getPersonEntry personUuid
    continue $
        state
        { cubStateShown =
              CubEditPerson
                  EditPersonState
                  { editPersonStateUuid = personUuid
                  , editPersonStateStartingEntry = mpe
                  , editPersonStatePropertyEditor =
                        propertyEditor "edit-person" $
                        personEntryProperties <$> mpe
                  }
        }
