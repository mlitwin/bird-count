import SpeciesName from '../common/SpeciesName'
import React, { useRef, useEffect } from 'react'
import List from '@mui/material/List'
import ListItem from '@mui/material/ListItem'

import './SpeciesPicker.css'

function setScrollPositionToEnd(bottomEl) {
    if (bottomEl.current) {
        bottomEl.current.scrollIntoView(false)
    }
}

function SpeciesPicker(props) {
    const bottomEl = useRef(null)
    const maxSpeciesInPicker = 100
    const species = props.species.slice(0, maxSpeciesInPicker).reverse()

    useEffect(() => {
        setScrollPositionToEnd(bottomEl)
    })

    useEffect(() => {
        setScrollPositionToEnd(bottomEl)
    }, [species])

    function itemContent(sp, index, bottomEl) {
        const itemProps: any = {
            key: `${sp.id}:${index}`,
            onClick: (e) => props.chooseItem(sp),
        }
        if (index === species.length - 1) {
            itemProps.ref = bottomEl
        }
        return (
            <ListItem {...itemProps}>
                <SpeciesName species={sp} />
            </ListItem>
        )
    }

    const listKey = species.map((s) => s.id).join(':')

    return (
        <List key={listKey} className="SpeciesPicker">
            {species.map((sp, index) => itemContent(sp, index, bottomEl))}
        </List>
    )
}

export default SpeciesPicker
