import SpeciesName from '../common/SpeciesName'
import React, { useRef, useEffect } from 'react'
import List from '@mui/material/List'
import ListItem from '@mui/material/ListItem'
import { Virtuoso } from 'react-virtuoso'

import './SpeciesPicker.css'

function SpeciesPicker(props) {
    const virtuoso = useRef(null)

    function virtuosoListIndex(index) {
        return props.species.length - index - 1
    }

    const lastIndex = props.species.length - 1

    useEffect(() => {
        if (virtuoso.current && lastIndex >= 0) {
            virtuoso.current.scrollToIndex({
                index: lastIndex,
                align: 'start',
                behavior: 'auto',
            })
        }
    }, [props.species])

    function itemContent(index) {
        const reveseIndex = virtuosoListIndex(index)
        const species = props.species[reveseIndex]
        return (
            <ListItem
                key={reveseIndex}
                onClick={(e) => props.chooseItem(reveseIndex)}
            >
                <SpeciesName species={species} />
            </ListItem>
        )
    }

    const listKey = props.species.map((s) => s.id).join('/')

    return (
        <List className="SpeciesPicker">
            <Virtuoso
                key={listKey}
                ref={virtuoso}
                totalCount={props.species.length}
                initialTopMostItemIndex={lastIndex}
                alignToBottom={true}
                itemContent={(index) => itemContent(index)}
            />
        </List>
    )
}

export default SpeciesPicker
