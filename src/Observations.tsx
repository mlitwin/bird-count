import ObservationEntry from './common/ObservationEntry'
import List from '@mui/material/List'
import ListItem from '@mui/material/ListItem'
import { Virtuoso } from 'react-virtuoso'
import * as React from 'react'
import './Observations.css'

function Observations(props) {
    function observationContent(index) {
        const observation = props.observations[index]
        console.log(
            `observationContent ${observation.id} ${observation.children}`
        )

        return (
            <ListItem>
                <ObservationEntry
                    observation={observation}
                    initialMode="display"
                />
            </ListItem>
        )
    }

    return (
        <div className="oneColumnExpand">
            <List className="Observations">
                <Virtuoso
                    totalCount={props.observations.length}
                    itemContent={(index) => observationContent(index)}
                />
            </List>
        </div>
    )
}

export default Observations
