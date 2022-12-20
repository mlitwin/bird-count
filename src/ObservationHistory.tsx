import * as React from 'react'
import Button from '@mui/material/Button'
import { Taxonomy, Observation, ObservationSet } from 'model/types'
import { ObservationList, IObservationGroup } from './common/ObservationList'
import ObservationEntry from './common/ObservationEntry'
import ListItem from '@mui/material/ListItem'
import { getAppContext } from './store/store'

import { observations, clearObservations } from './store/store'

import dayjs from 'dayjs'

function observationGroupContent(group) {
    const date = dayjs.unix(group.date).format('ddd MM/D/YY')
    return (
        <ListItem>
            <ObservationEntry
                variant="header"
                observation={group.summary}
                initialMode="display"
                displayDate={date}
                displaySummary={group.statistics}
            />
        </ListItem>
    )
}
function observationContent(observation) {
    const date = dayjs(observation.start).format('HH:mm')

    return (
        <ListItem>
            <ObservationEntry
                variant="entry"
                observation={observation}
                initialMode="display"
                displayDate={date}
            />
        </ListItem>
    )
}

function setGroupOffsets(data: IObservationGroup[]) {
    let offset = 0
    data.forEach((g) => {
        g.offset = offset
        offset += g.observations.length
    })
}

function dayHistory(observations: Observation[]): IObservationGroup[] {
    const o = {}

    observations.forEach((obs) => {
        const date = obs.start
        const day = dayjs(date).startOf('date').unix()

        if (!o[day]) {
            o[day] = []
        }
        o[day].push(obs)
    })

    const observationKeys = Object.keys(o).sort((a, b) => {
        return Number(a) - Number(b)
    })

    const ret = []
    observationKeys.forEach((g) => {
        const group = {
            date: Number(g),
            summary: new ObservationSet(o[g]),
            statistics: '',
            observations: o[g]
                .sort((a, b) => {
                    return a.start - b.start
                })
                .map((obs) => new ObservationSet([obs]))
                .filter((o) => o.count > 0),
        }

        ret.push(group)
    })

    setGroupOffsets(ret)
    return ret
}

function countSpecies(taxonomy: Taxonomy, observations: Observation[]): number {
    let ret = 0

    const counted: { [id: string]: Boolean } = {}

    observations.forEach((obs) => {
        let t = obs.species.id
        if (!counted[t]) {
            ret++
            while (t && !counted[t]) {
                counted[t] = true
                t = taxonomy.speciesTaxons[t].parent
            }
        }
    })
    return ret
}

function daySummary(dayHistory: IObservationGroup[]): IObservationGroup[] {
    const ac = getAppContext()
    const ret = dayHistory.map((g) => {
        const ng = { ...g }
        const obsBySpecies: { [key: string]: ObservationSet } = {}
        ng.observations.forEach((obs) => {
            const sp = ac.taxonomy.speciesTaxon(obs.species)
            if (!obsBySpecies[sp.id]) {
                obsBySpecies[sp.id] = new ObservationSet([obs])
            } else {
                obsBySpecies[sp.id].Union(ac.taxonomy, obs)
            }
        })
        const obsSummaries: ObservationSet[] = []
        for (let k in obsBySpecies) {
            obsSummaries.push(obsBySpecies[k])
        }

        ng.observations = obsSummaries.sort(
            (a, b) => a.species.taxonomicOrder - b.species.taxonomicOrder
        )

        const speciesCount = countSpecies(ac.taxonomy, ng.observations)

        ng.statistics = `${speciesCount} species`

        return ng
    })

    setGroupOffsets(ret)
    return ret
}

function ObservationHistory(props) {
    const obs = observations()
    const parentObs = obs.filter((o) => o.parent == null)
    const olist = parentObs.map((o) => o.toJSONObject())
    const data = dayHistory(parentObs)

    if (props.mode === 'summary') {
        return ObservationHistorySummary(daySummary(data))
    }

    return ObservationHistoryLog(olist, data)
}

function ObservationHistoryLog(olist, data) {
    const mail = encodeURIComponent(JSON.stringify(olist, null, 2))
    const mailto = `mailto:?body=${mail}&subject=Email the List`

    function doClear() {
        clearObservations()
    }

    return (
        <div className="oneColumn">
            <ObservationList
                data={data}
                observationGroupContent={observationGroupContent}
                observationContent={observationContent}
            />
            <Button variant="contained" onClick={(e) => doClear()}>
                CLEAR
            </Button>
            <a href={mailto}>Email the List</a>
        </div>
    )
}

function ObservationHistorySummary(data) {
    return (
        <div className="oneColumn">
            <ObservationList
                data={data}
                observationGroupContent={observationGroupContent}
                observationContent={observationContent}
            />
        </div>
    )
}

export default ObservationHistory
