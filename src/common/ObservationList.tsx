import { ObservationSet } from 'model/types'
import List from '@mui/material/List'
import { GroupedVirtuoso } from 'react-virtuoso'
import React, { useEffect, useRef } from 'react'
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
    observationGroupContent: (group: any) => JSX.Element
    observationContent: (item: any) => JSX.Element
}

function ObservationList(props: IObservationListProps) {
    const data = props.data

    const groupCounts = data.map((g) => g.observations.length)
    const groupedVirtuosoProps: any = {
        groupCounts: groupCounts,
        groupContent: (index) => props.observationGroupContent(data[index]),
        itemContent: (i, g) =>
            props.observationContent(data[g].observations[i - data[g].offset]),
        components: { TopItemList: 'div' },
    }
    const totalObservations = groupCounts.reduce((g, current) => g + current, 0)

    if (totalObservations > 0) {
        groupedVirtuosoProps.initialTopMostItemIndex = totalObservations - 1
    }

    const virtuoso = useRef(null)

    useEffect(() => {
        if (virtuoso.current) {
            if (totalObservations > 0) {
                virtuoso.current.scrollToIndex({
                    index: totalObservations - 1,
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

export { ObservationList, IObservationGroup }
