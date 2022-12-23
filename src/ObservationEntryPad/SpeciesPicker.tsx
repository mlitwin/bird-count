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

    const lastIndex = props.species.length - 1

    /* Safari workaround.
        On initial load, the last item renders as expected, but
        then somehow it restarts from item 1 (second item) - scrolls almost to the top
        chrome doesn't.
    */
    useEffect(() => {
        setTimeout(() => setScrollPosition(virtuoso), 100)
    }, [])

    useEffect(() => {
        setScrollPosition(virtuoso)
    }, [props.species, lastIndex])

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

    return (
        <List className="SpeciesPicker">
            <Virtuoso
                ref={virtuoso}
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
