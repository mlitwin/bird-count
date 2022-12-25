import SpeciesName from '../common/SpeciesName'
import React, { useRef, useEffect } from 'react'
import List from '@mui/material/List'
import ListItem from '@mui/material/ListItem'
import { Virtuoso } from 'react-virtuoso'

import './SpeciesPicker.css'

function setScrollPosition(virtuoso) {
    if (virtuoso.current) {
        virtuoso.current.scrollToIndex({
            index: 'LAST',
            align: 'start',
            behavior: 'auto',
        })
    }
}

function SpeciesPicker(props) {
    const virtuoso = useRef(null)

    function virtuosoListIndex(index) {
        return props.species.length - index - 1
    }

    // Needed for Safari - initialTopMostItemIndex doesn't seem to work?
    useEffect(() => {
        setTimeout(() => setScrollPosition(virtuoso), 100)
    })

    useEffect(() => {
        setScrollPosition(virtuoso)
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

    function itemKey(index) {
        const reveseIndex = virtuosoListIndex(index)
        const species = props.species[reveseIndex]
        return species.id
    }

    const listKey = props.species.map((s) => s.id).join(':')

    return (
        <List className="SpeciesPicker">
            <Virtuoso
                key={listKey}
                ref={virtuoso}
                style={{ height: '100%' }}
                totalCount={props.species.length}
                initialTopMostItemIndex={{
                    index: 'LAST',
                    align: 'start',
                    behavior: 'auto',
                }}
                computeItemKey={itemKey}
                alignToBottom={true}
                itemContent={(index) => itemContent(index)}
            />
        </List>
    )
}

export default SpeciesPicker
