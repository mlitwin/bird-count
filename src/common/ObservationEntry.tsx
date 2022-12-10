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
    type: 'accept' | 'cancel'
    observation: Observation
}

interface ObservationProps {
    initialMode: Modes
    observation: Observation
    onEvent?: (event: IObservationEntryEvent) => void
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

    function onClick() {
        props.setMode('edit')
    }

    return (
        <div className="Observation display" onClick={onClick}>
            <div className="ObservationHeader">
                <div className="ObservationCount">{count}</div>
                <SpeciesName species={species}></SpeciesName>
            </div>
        </div>
    )
}

function ObservationEntryEdit(props) {
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
                observation: props.observation,
            })
        }
    }

    function doCancel() {
        props.setMode('display')

        if (props.onEvent) {
            props.onEvent({
                type: 'cancel',
                observation: props.observation,
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
                    <MoreMenu doCancel={doCancel}></MoreMenu>
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

    const query = new ObservationSet([props.observation])

    if (mode === 'display') {
        return (
            <ObservationEntryDisplay
                query={query}
                setMode={setMode}
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
