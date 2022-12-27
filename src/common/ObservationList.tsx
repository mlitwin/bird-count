import { ObservationSet } from 'model/types'
import List from '@mui/material/List'
import { GroupedVirtuoso } from 'react-virtuoso'
import React, { useEffect, useRef, useState } from 'react'
import './ObservationList.css'

interface IObservationGroup {
    date: number
    summary: ObservationSet
    statistics: string
    offset: number
    observations: ObservationSet[]
}

interface IObservationListProps {
    data: IObservationGroup[]
    observationGroupContent: (group: any, isScrolling: boolean) => JSX.Element
    observationContent: (item: any, isScrolling: boolean) => JSX.Element
}

function EmptyObservationList() {
    return (
        <div className="oneColumnExpand">
            <List className="Observations"></List>
        </div>
    )
}

function ObservationList(props: IObservationListProps) {
    const data = props.data
    const [isScrolling, setIsScrolling] = useState(false)

    const virtuoso = useRef(null)
    useEffect(() => {
        if (virtuoso && virtuoso.current) {
            virtuoso.current.scrollToIndex({
                index: 'LAST',
                align: 'start',
                behavior: 'auto',
            })
        }
    }, [data])

    const groupCounts = data.map((g) => g.observations.length)
    const totalObservations = groupCounts.reduce((g, current) => g + current, 0)

    if (totalObservations === 0) {
        return EmptyObservationList()
    }

    const groupedVirtuosoProps: any = {
        groupCounts: groupCounts,
        groupContent: (index) =>
            props.observationGroupContent(data[index], isScrolling),
        itemContent: (i, g) =>
            props.observationContent(
                data[g].observations[i - data[g].offset],
                isScrolling
            ),
        initialTopMostItemIndex: totalObservations - 1,
        isScrolling: setIsScrolling,
    }

    return (
        <div className="oneColumnExpand">
            <List className="Observations">
                <GroupedVirtuoso ref={virtuoso} {...groupedVirtuosoProps} />
            </List>
        </div>
    )
}

export { ObservationList, IObservationGroup }
