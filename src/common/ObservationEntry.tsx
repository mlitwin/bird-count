import React, { useState, useRef } from 'react'
import SpeciesName from './SpeciesName'
import { ObservationSet, Observation } from 'model/types'
import IconButton from '@mui/material/IconButton'
import Button from '@mui/material/Button'
import {
    CheckCircleOutline,
    AddCircleOutline,
    RemoveCircleOutlined,
    CancelOutlined,
} from '@mui/icons-material'
import { useSwipeable } from 'react-swipeable'

import { getAppContext, useAddObservation } from '../store/store'

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
    displaySummary?: string
    onEvent?: ObservationEntryEventCallback
    isScrolling: boolean
}

function useRevealSwiper(cancel: boolean) {
    const last = useRef(null)
    const [activeSlide, setActiveSlide] = useState('middle')
    const [lastWidth, setLastWidth] = useState(0)
    const [lastContentWidth, setLastContentWidth] = useState(0)
    const [canceled, setCanceled] = useState(false)

    function setWidth(width) {
        setLastWidth(Math.max(width, 0))
    }

    function endSwipe() {
        const offsetWidth = last?.current.offsetWidth
        const scrollWidth = last?.current.scrollWidth
        if (canceled) {
            setCanceled(false)
        }
        if (offsetWidth < scrollWidth) {
            setLastWidth(0)
            setActiveSlide('middle')
        } else {
            setActiveSlide('last')
        }
    }

    function doCancel() {
        if (cancel) {
            setCanceled(true)
            endSwipe()
        }
        return cancel
    }

    const handlers = useSwipeable({
        onSwipeStart: (eventData) => {
            if (doCancel()) {
                return
            }
            if (activeSlide === 'last') {
                setLastContentWidth(last.current.offsetWidth)
            }
        },
        onSwiping: (eventData) => {
            if (canceled) {
                return
            }
            if (doCancel()) {
                return
            }
            if (activeSlide === 'middle') {
                const w = Math.floor(-eventData.deltaX)
                setWidth(w)
            }
            if (activeSlide === 'last') {
                const w = Math.floor(lastContentWidth - eventData.deltaX)
                setWidth(w)
            }
        },
        onSwiped: (eventData) => {
            endSwipe()
        },
        trackMouse: true,
        preventScrollOnSwipe: true,
        delta: 20,
    })

    const lastProps = {
        ref: last,
        style: {
            width: lastWidth,
        },
    }
    const swiperProps = {
        className: `ObservatioSwiper ${activeSlide}`,
    }
    return [handlers, swiperProps, lastProps]
}

function ObservationEntryDisplay(props) {
    const query = props.query
    const count = props.query.count
    const species = props.query.species
    const date = props.displayDate
    const addObservation = useAddObservation()

    const [handlers, swiperProps, lastProps] = useRevealSwiper(
        props.isScrolling
    )

    function onClick() {
        props.setMode('edit')

        if (props.onEvent) {
            props.onEvent({
                type: 'edit',
                observation: props.query,
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

    return (
        <div {...swiperProps} {...handlers}>
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
                    <div>{props.displaySummary}</div>
                </div>
            </div>
            <div className="last" {...lastProps}>
                <Button
                    className="DeleteObservatiobButton"
                    onClick={(e) => doDelete()}
                >
                    Delete
                </Button>
            </div>
        </div>
    )
}

interface IObservationEntryEditProps {
    query: ObservationSet
    variant: string
    setMode: any
    onEvent?: ObservationEntryEventCallback
}

function ObservationEntryEdit(props: IObservationEntryEditProps) {
    const query = props.query
    const addObservation = useAddObservation()

    const [count, setCount] = useState(query.count)
    const ac = getAppContext()

    const delta = count - query.count

    function doAccept() {
        if (props.variant === 'create') {
            addObservation(query)
        } else if (delta !== 0) {
            const child = ac.createObservation()
            child.parent = query.newObservationParent()
            child.species = child.parent ? child.parent.species : query.species
            child.count = delta

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

    const activeEdit =
        props.variant === 'create' || delta !== 0
            ? 'activeEdit'
            : 'noActiveEdit'

    return (
        <div className={'Observation edit ' + activeEdit}>
            <div className="ObservationHeader">
                <SpeciesName species={query.species}></SpeciesName>
            </div>
            <div className="ObservationEditIcons">
                <div className="EntryControls">
                    <IconButton className="Button" onClick={(e) => doCancel()}>
                        <CancelOutlined fontSize="large" />
                    </IconButton>
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
        const displaySummary = props.displaySummary ? props.displaySummary : ''
        return (
            <ObservationEntryDisplay
                key={query.id}
                variant={props.variant}
                query={query}
                setMode={setMode}
                displayDate={displayDate}
                displaySummary={displaySummary}
                onEvent={props.onEvent}
                isScrolling={props.isScrolling}
            ></ObservationEntryDisplay>
        )
    }

    return (
        <ObservationEntryEdit
            query={query}
            variant={props.variant}
            setMode={setMode}
            onEvent={props.onEvent}
        ></ObservationEntryEdit>
    )
}

export default ObservationEntry
export { ObservationEntry }
