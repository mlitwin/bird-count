import * as React from 'react'
import { ObservationSet } from 'model/types'
import { ObservationList } from './common/ObservationList'
import ObservationEntry from './common/ObservationEntry'
import ListItem from '@mui/material/ListItem'

import { observations } from './store/store'

import dayjs from 'dayjs'

function ObservationHistory(props) {
    const allObservations = observations()

    const obs = allObservations
        .filter((o) => o.parent === null)
        .map((o) => new ObservationSet([o]))
        .filter((o) => o.count > 0)
        .sort((a, b) => {
            return a.start - b.start
        })

    function observationContent(observation, index, isScrolling) {
        const observationDate = dayjs(observation.start)
        const observationDay = observationDate.startOf('date')

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
                        isScrolling={isScrolling}
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
