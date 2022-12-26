import Keypad from './ObservationEntryPad/Keypad'
import SpeciesPicker from './ObservationEntryPad/SpeciesPicker'
import FilterBar from './ObservationEntryPad/FilterBar'
import { ObservationEntry } from './common/ObservationEntry'

import { Observation, ObservationSet } from './model/types'

import { getAppContext, recentObservations } from './store/store'
import React, { useState } from 'react'

import './ObservationEntryPad.css'

function filterSortIndex(filter, species) {
    var ret: number = 0

    if (filter === '') {
        return ret
    }
    const f = filter.toUpperCase()

    ret--

    for (let i = 1; i <= species.abbreviations.length; i++) {
        const abbrv = species.abbreviations[i - 1]
        if (abbrv.startsWith(f)) {
            return ret
        }
    }

    ret--
    const name = species.localizations.en.commonName
        .toUpperCase()
        .replace(/[^A-Z]/g, '')

    const nf = name.indexOf(f)
    if (nf === 0) {
        return ret
    }
    ret--
    if (nf > 0) {
        return ret
    }

    return 0
}

function standardSortLevel(species) {
    return species.commonness
}

function computeChecklist(ck, filter, recent, latest) {
    let species = []
    const filterSort = {}
    const standardSort = {}
    const recentSort = {}
    const latestId = latest ? latest.species.id : ''

    if (ck) {
        ck.species.forEach((s) => {
            if (s.id === latestId) {
                return
            }
            const st = standardSortLevel(s)
            if (st < filter.commonness) {
                return
            }
            const l = filterSortIndex(filter.text, s)
            filterSort[s.id] = l
            standardSort[s.id] = st
            recentSort[s.id] = 0

            if (!filter.text || l !== 0) {
                species.push(s)
            }
        })
    }

    let recentIndex = 1
    recent.forEach((obs) => {
        const id = obs.species.id
        if (!recentSort[id]) {
            recentSort[id] = recentIndex
            recentIndex++
        }
    })

    species = species.sort((a, b) => {
        return (
            filterSort[b.id] - filterSort[a.id] ||
            standardSort[b.id] - standardSort[a.id] ||
            recentSort[b.id] - recentSort[a.id]
        )
    })

    return species
}

interface IFilter {
    text: string
    commonness: number
}

const defaultFilter = {
    text: '',
    commonness: 2,
}

function ObservationEntryPad(props) {
    const [filter, setFilter] = useState<IFilter>(defaultFilter)
    const [activeObservation, setActiveObservation] =
        useState<null | Observation>(null)

    const recent = recentObservations()
    const ac = getAppContext()
    const checklist = ac.checklist

    const species = computeChecklist(
        checklist,
        filter,
        recent,
        activeObservation
    )

    function resetInput() {
        setFilter(defaultFilter)
    }

    function chooseItem(sp) {
        const newObservation = ac.createObservation()
        newObservation.species = sp
        newObservation.count = 1

        setActiveObservation(newObservation)

        resetInput()
    }

    function onEvent() {
        setActiveObservation(null)
    }

    const editActive = activeObservation ? 'editActive' : 'editNotActive'

    function observationEntry() {
        if (activeObservation === null) {
            return <div className="ObservationSummaryPlaceholder"></div>
        }
        return (
            <ObservationEntry
                variant="create"
                key={activeObservation.id}
                onEvent={onEvent}
                observation={new ObservationSet([activeObservation])}
                initialMode="edit"
            />
        )
    }

    return (
        <div className={'ObservationEntryPad oneColumn ' + editActive}>
            <div className="ObservationListArea oneColumnExpand">
                <SpeciesPicker species={species} chooseItem={chooseItem} />
            </div>
            {observationEntry()}
            <FilterBar filter={filter} setFilter={setFilter} />
            <Keypad filter={filter} setFilter={setFilter} />
        </div>
    )
}

export default ObservationEntryPad
