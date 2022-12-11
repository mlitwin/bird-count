import ObservationEntry from './common/ObservationEntry'
import { Observation, ObservationSet } from 'model/types'
import List from '@mui/material/List'
import ListItem from '@mui/material/ListItem'
import { GroupedVirtuoso } from 'react-virtuoso'
import React, { useEffect, useRef } from 'react'
import './Observations.css'

import dayjs from 'dayjs'

function dayHistory(observations: Observation[]) {
    const o = {}

    observations.forEach((obs) => {
        const date = obs.start
        const day = dayjs(date).startOf('date').unix()

        if (!o[day]) {
            o[day] = []
        }
        o[day].push(obs)
    })

    let offset = 0

    const ret = Object.keys(o)
        .sort((a, b) => {
            return Number(a) - Number(b)
        })
        .map((g) => {
            const group = {
                date: Number(g),
                summary: new ObservationSet(o[g]),
                offset: offset,
                observations: o[g]
                    .sort((a, b) => {
                        return a.start - b.start
                    })
                    .map((obs) => new ObservationSet([obs])),
            }
            offset += group.observations.length

            return group
        })
    return ret
}

function Observations(props) {
    function observationGroupContent(group) {
        const date = dayjs.unix(group.date).format('ddd MM/D/YY')
        return (
            <ListItem>
                <ObservationEntry
                    variant="header"
                    observation={group.summary}
                    initialMode="display"
                    displayDate={date}
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

    const hist = dayHistory(props.observations)
    const groupCounts = hist.map((g) => g.observations.length)
    const groupedVirtuosoProps: any = {
        groupCounts: groupCounts,
        groupContent: (index) => observationGroupContent(hist[index]),
        itemContent: (i, g) =>
            observationContent(hist[g].observations[i - hist[g].offset]),
        components: { TopItemList: React.Fragment },
    }

    if (props.observations.length > 0) {
        groupedVirtuosoProps.initialTopMostItemIndex =
            props.observations.length - 1
    }

    const virtuoso = useRef(null)

    useEffect(() => {
        if (virtuoso.current) {
            if (props.observations.length > 0) {
                virtuoso.current.scrollToIndex({
                    index: props.observations.length - 1,
                    align: 'start',
                    behavior: 'auto',
                })
            }
        }
    })

    return (
        <div className="oneColumnExpand">
            <List className="Observations">
                <GroupedVirtuoso ref={virtuoso} {...groupedVirtuosoProps} />
            </List>
        </div>
    )
}

export default Observations
