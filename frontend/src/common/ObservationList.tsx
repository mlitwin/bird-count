import { ObservationSet } from 'model/types'
import List from '@mui/material/List'
import { Virtuoso } from 'react-virtuoso'
import React, { useEffect, useRef, useState } from 'react'
import './ObservationList.css'

interface IObservationListProps {
    data: ObservationSet[]
    observationContent: (
        observation: any,
        index: any,
        isScrolling: boolean
    ) => JSX.Element
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

    const totalObservations = data.length

    if (totalObservations === 0) {
        return EmptyObservationList()
    }

    const vrtuosoProps: any = {
        totalCount: totalObservations,
        itemContent: (i) => props.observationContent(data[i], i, isScrolling),
        initialTopMostItemIndex: totalObservations - 1,
        isScrolling: setIsScrolling,
    }

    return (
        <div className="oneColumnExpand">
            <List className="Observations">
                <Virtuoso ref={virtuoso} {...vrtuosoProps} />
            </List>
        </div>
    )
}

export { ObservationList }
