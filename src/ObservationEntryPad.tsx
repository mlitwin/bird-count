import Keypad from './ObservationEntryPad/Keypad'
import SpeciesPicker from './ObservationEntryPad/SpeciesPicker'
import FilterBar from './ObservationEntryPad/FilterBar'
import { ObservationEntry, createObservation } from './common/ObservationEntry'

import { Observation } from './model/types'

import { recentObservations, useAddObservation } from './store/store'
import React, { useState } from 'react'

import './ObservationEntryPad.css'

function filterLevel(filter, species): number {
    var ret: number = 0

    if (!species.standard) {
        return 0
    }

    if (filter === '') {
        return 1
    }

    const f = filter.toUpperCase()

    for (ret = 1; ret <= species.abbreviations.length; ret++) {
        const abbrv = species.abbreviations[ret - 1]
        if (abbrv.startsWith(f)) {
            return ret
        }
    }
    const name = species.localizations.en.commonName
        .toUpperCase()
        .replace(/[^A-Z]/g, '')

    const nf = name.indexOf(f)
    if (nf === 0) {
        return ret
    }
    ret++
    if (nf > 0) {
        return ret
    }

    ret = 0

    return ret
}

function computeChecklist(ck, filter, recent, latest) {
    let species = []
    const levels = {}
    const latestId = latest ? latest.species.id : ''

    if (ck) {
        ck.species.forEach((s) => {
            if (s.id === latestId) {
                return
            }
            const l = filterLevel(filter, s)
            if (l > 0) {
                species.push(s)
                levels[s.id] = l
            }
        })
    }

    // Recent ones first
    const recentOrder = {}
    let recentIndex = 1
    recent.forEach((obs) => {
        if (!(obs.species.id in recentOrder)) {
            recentOrder[obs.species.id] = recentIndex
            recentIndex++
        }
    })

    species = species.sort((a, b) => {
        const lcmp = levels[a.id] - levels[b.id]
        if (lcmp !== 0) {
            return lcmp
        }

        let aIndex = a.taxonomicOrder
        let bIndex = b.taxonomicOrder

        if (a.id in recentOrder) {
            aIndex = -(recent.length - recentOrder[a.id])
        }
        if (b.id in recentOrder) {
            bIndex = -(recent.length - recentOrder[b.id])
        }

        return aIndex - bIndex
    })

    return species
}

function ObservationEntryPad(props) {
    const [active, setActiveState] = useState(0)
    const [filter, setFilter] = useState('')
    const [activeObservation, setActiveObservation] =
        useState<null | Observation>(null)

    const addObservation = useAddObservation()
    const recent = recentObservations()
    const checklist = props.observationContext.checklist

    const species = computeChecklist(
        checklist,
        filter,
        recent,
        activeObservation
    )

    function resetInput() {
        setFilter('')
        setActiveState(0)
    }

    function chooseItem(index) {
        if (species.length === 0) {
            return
        }

        if (index === undefined) {
            index = active
        }

        const newObservation = createObservation(
            props.observationContext.taxonomy,
            species[index]
        )

        addObservation(newObservation)
        setActiveObservation(newObservation)

        resetInput()
    }

    function onEvent() {
        setActiveObservation(null)
    }

    const editActive = activeObservation ? 'editActive' : 'editNotActive'

    function observationEntry() {
        if (activeObservation === null) {
            return <div className="ObservationSummary placeholder"></div>
        }
        return (
            <ObservationEntry
                key={activeObservation.id}
                onEvent={onEvent}
                observation={activeObservation}
                initialMode="edit"
            />
        )
    }

    return (
        <div className={'ObservationEntryPad oneColumn ' + editActive}>
            <div className="ObservationListArea oneColumnExpand">
                <SpeciesPicker
                    species={species}
                    active={active}
                    chooseItem={chooseItem}
                />
            </div>
            {observationEntry()}
            <FilterBar
                filter={filter}
                setFilter={setFilter}
                chooseItem={chooseItem}
            />
            <Keypad filter={filter} setFilter={setFilter} />
        </div>
    )
}

export default ObservationEntryPad
