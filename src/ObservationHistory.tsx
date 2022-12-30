import * as React from 'react'
import Button from '@mui/material/Button'
import { ObservationSet } from 'model/types'
import { ObservationList } from './common/ObservationList'
import ObservationEntry from './common/ObservationEntry'
import ListItem from '@mui/material/ListItem'

import { observations, clearObservations } from './store/store'

import dayjs from 'dayjs'

function ObservationHistory(props) {
    const allObservations = observations()

    const observationsJSON = allObservations.map((o) => o.toJSONObject())
    const mail = encodeURIComponent(JSON.stringify(observationsJSON, null, 2))
    const mailto = `mailto:?body=${mail}&subject=Email the List`
    const obs = allObservations
        .filter((o) => o.parent === null)
        .map((o) => new ObservationSet([o]))
        .filter((o) => o.count > 0)
        .sort((a, b) => {
            return a.start - b.start
        })

    function doClear() {
        clearObservations()
    }

    function observationContent(observation, index, isScrolling) {
        const observationDate = dayjs(observation.start)
        const observationDay = observationDate.startOf('date')

        const isFirstOfDay =
            index === 0 ||
            observationDay === dayjs(obs[index - 1].start).startOf('date')

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
            <Button variant="contained" onClick={(e) => doClear()}>
                CLEAR
            </Button>
            <a href={mailto}>Email the List</a>
        </div>
    )
}

export default ObservationHistory
