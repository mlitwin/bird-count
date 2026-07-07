import * as React from 'react'
import { ObservationSet, Observation } from './model/types'
import { ObservationList } from './common/ObservationList'
import ObservationEntry from './common/ObservationEntry'
import ListItem from '@mui/material/ListItem'

import { observations } from './store/store'

import dayjs, { Dayjs } from 'dayjs'

interface ObservationHistoryProps {}

function ObservationHistory(props: ObservationHistoryProps) {
    const allObservations = observations()

    const obs: ObservationSet[] = allObservations
        .filter((o: Observation) => o.parent === null)
        .map((o: Observation) => new ObservationSet([o]))
        .filter((o: ObservationSet) => o.count > 0)
        .sort((a: ObservationSet, b: ObservationSet) => {
            return a.start - b.start
        })

    function observationContent(
        observation: ObservationSet,
        index: number,
        isScrolling: boolean
    ) {
        const observationDate = dayjs(observation.start)
        const observationDay: Dayjs = observationDate.startOf('date')

        const isFirstOfDay =
            index === 0 ||
            observationDay.unix() !==
                dayjs(obs[index - 1].start)
                    .startOf('date')
                    .unix()

        const date = observationDate.format('HH:mm')

        return (
            <ListItem key={observation.id}>
                <div className="ObservationListItem">
                    {isFirstOfDay && (
                        <div className="ObservationListDayHeader">
                            {observationDay.format('ddd MM/D/YY')}
                        </div>
                    )}
                    <ObservationEntry
                        variant="entry"
                        observation={observation}
                        initialMode="display"
                        displayDate={date}
                        disableSwipe={isScrolling}
                    />
                </div>
            </ListItem>
        )
    }

    return (
        <div className="oneColumn">
            <ObservationList
                data={obs}
                observationContent={observationContent}
            />
        </div>
    )
}

export default ObservationHistory
