import * as React from 'react'
import Button from '@mui/material/Button'
import { Observation, ObservationSet } from 'model/types'
import { ObservationList, IObservationGroup } from './common/ObservationList'
import ObservationEntry from './common/ObservationEntry'
import ListItem from '@mui/material/ListItem'

import { observations, clearObservations } from './store/store'

import dayjs from 'dayjs'

function observationGroupContent(group, isScrolling) {
    const date = dayjs.unix(group.date).format('ddd MM/D/YY')
    return (
        <ListItem>
            <ObservationEntry
                variant="header"
                observation={group.summary}
                initialMode="display"
                displayDate={date}
                displaySummary={group.statistics}
                isScrolling={isScrolling}
            />
        </ListItem>
    )
}
function observationContent(observation, isScrolling) {
    const date = dayjs(observation.start).format('HH:mm')

    return (
        <ListItem>
            <ObservationEntry
                variant="entry"
                observation={observation}
                initialMode="display"
                displayDate={date}
                isScrolling={isScrolling}
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

function ObservationHistory(props) {
    const obs = observations()
    const parentObs = obs.filter((o) => o.parent == null)
    const olist = parentObs.map((o) => o.toJSONObject())
    const data = dayHistory(parentObs)

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

export default ObservationHistory
