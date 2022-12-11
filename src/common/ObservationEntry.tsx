import React, { useState } from 'react'
import SpeciesName from './SpeciesName'
import MoreMenu from './ObservationEntry/MoreMenu'
import { ObservationSet, Observation, Taxonomy, Species } from 'model/types'
import IconButton from '@mui/material/IconButton'
import {
    CheckCircleOutline,
    AddCircleOutline,
    RemoveCircleOutlined,
} from '@mui/icons-material'

import { useAddObservation } from '../store/store'

import { v4 as uuidv4 } from 'uuid'

import './ObservationEntry.css'

type Modes = 'display' | 'edit'

interface IObservationEntryEvent {
    type: 'edit' | 'accept' | 'cancel' | 'delete'
    observation: ObservationSet
}

type ObservationEntryEventCallback = (event: IObservationEntryEvent) => void

interface ObservationProps {
    initialMode: Modes
    observation: ObservationSet
    variant: 'create' | 'header' | 'entry'
    displayDate?: string
    onEvent?: ObservationEntryEventCallback
}

function createObservation(taxonomy: Taxonomy, species: Species): Observation {
    const now = Date.now()
    let obs = new Observation()

    obs.id = uuidv4()
    obs.createdAt = now
    obs.start = now
    obs.duration = 0
    obs.taxonomy = taxonomy
    obs.species = species
    obs.count = 1
    obs.parent = null

    return obs
}

function createChildObservation(
    parent: Observation,
    count: number
): Observation {
    const now = Date.now()
    let obs = new Observation()

    obs.id = uuidv4()
    obs.createdAt = now
    obs.start = now
    obs.duration = 0
    obs.taxonomy = parent.taxonomy
    obs.species = parent.species
    obs.count = count
    obs.parent = parent

    return obs
}

function ObservationEntryDisplay(props) {
    const count = props.query.count
    const species = props.query.species
    const date = props.displayDate

    function onClick() {
        props.setMode('edit')

        if (props.onEvent) {
            props.onEvent({
                type: 'edit',
                observation: props.query,
            })
        }
    }

    return (
        <div
            className={'Observation display ' + props.variant}
            onClick={onClick}
        >
            <div className="ObservationDisplay">
                <div className="ObservationDate">{date}</div>
                <div className="ObservationSummary">
                    <div className="ObservationCount">{count}</div>
                    <SpeciesName species={species}></SpeciesName>
                </div>
            </div>
        </div>
    )
}

interface IObservationEntryEditProps {
    query: ObservationSet
    setMode: any
    onEvent?: ObservationEntryEventCallback
}

function ObservationEntryEdit(props: IObservationEntryEditProps) {
    const query = props.query
    const addObservation = useAddObservation()

    const [count, setCount] = useState(query.count)

    const delta = count - query.count

    function doAccept() {
        if (delta !== 0) {
            const child = createChildObservation(
                query.newObservationParent(),
                delta
            )
            addObservation(child)
        }

        props.setMode('display')

        if (props.onEvent) {
            props.onEvent({
                type: 'accept',
                observation: query,
            })
        }
    }

    function doCancel() {
        props.setMode('display')

        if (props.onEvent) {
            props.onEvent({
                type: 'cancel',
                observation: query,
            })
        }
    }

    function doDelete() {
        props.setMode('display')

        const deleteObservations = query.observations.map((o) => {
            const parentSet = new ObservationSet([o])
            const newO = new Observation()
            newO.Assign(o)
            newO.createdAt = Date.now()
            newO.id = uuidv4()
            newO.count = -parentSet.count
            newO.parent = o

            return newO
        })

        deleteObservations.forEach((o) => {
            addObservation(o)
        })

        if (props.onEvent) {
            props.onEvent({
                type: 'delete',
                observation: query,
            })
        }
    }

    const activeEdit = delta !== 0 ? 'activeEdit' : 'noActiveEdit'

    return (
        <div className={'Observation edit ' + activeEdit}>
            <div className="ObservationHeader">
                <SpeciesName species={query.species}></SpeciesName>
            </div>
            <div className="ObservationEditIcons">
                <div className="EntryControls">
                    <MoreMenu
                        doCancel={doCancel}
                        doDelete={doDelete}
                    ></MoreMenu>
                </div>
                <div className="CountEntry">
                    <div className="ObservationCount">{count}</div>
                    <IconButton
                        className="Button"
                        onClick={(e) => setCount(count - 1)}
                        disabled={count <= 1}
                    >
                        <RemoveCircleOutlined fontSize="large" />
                    </IconButton>
                    <IconButton
                        className="Button"
                        onClick={(e) => setCount(count + 1)}
                    >
                        <AddCircleOutline fontSize="large" />
                    </IconButton>
                </div>
                <IconButton
                    className="Button PrimaryButton"
                    onClick={(e) => doAccept()}
                >
                    <CheckCircleOutline fontSize="large" />
                </IconButton>
            </div>
        </div>
    )
}

function ObservationEntry(props: ObservationProps) {
    const [mode, setMode] = useState<Modes>(props.initialMode)

    const query = props.observation

    if (mode === 'display') {
        const displayDate = props.displayDate ? props.displayDate : ''
        return (
            <ObservationEntryDisplay
                variant={props.variant}
                query={query}
                setMode={setMode}
                displayDate={displayDate}
                onEvent={props.onEvent}
            ></ObservationEntryDisplay>
        )
    }

    return (
        <ObservationEntryEdit
            query={query}
            setMode={setMode}
            onEvent={props.onEvent}
        ></ObservationEntryEdit>
    )
}

export default ObservationEntry
export { ObservationEntry, createObservation }
