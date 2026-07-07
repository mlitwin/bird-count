import SpeciesName from '../common/SpeciesName'
import React, { useRef, useEffect } from 'react'
import List from '@mui/material/List'
import ListItem from '@mui/material/ListItem'
import { Species } from '../model/types'

import './SpeciesPicker.css'

function setScrollPositionToEnd(bottomEl: React.RefObject<HTMLElement | null>) {
    if (bottomEl.current) {
        bottomEl.current.scrollIntoView(false)
    }
}

interface SpeciesPickerProps {
    species: Species[]
    chooseItem: (species: Species) => void
}

function SpeciesPicker(props: SpeciesPickerProps) {
    const bottomEl = useRef<HTMLElement | null>(null)
    const maxSpeciesInPicker = 100
    const species = props.species.slice(0, maxSpeciesInPicker).reverse()

    useEffect(() => {
        setScrollPositionToEnd(bottomEl)
    })

    useEffect(() => {
        setScrollPositionToEnd(bottomEl)
    }, [species])

    function itemContent(sp: Species, index: number) {
        const key = `${sp.id}:${index}`
        const refProp = index === species.length - 1 ? bottomEl : undefined
        return (
            <ListItem
                key={key}
                ref={refProp as any}
                onClick={() => props.chooseItem(sp)}
            >
                <SpeciesName species={sp} />
            </ListItem>
        )
    }

    const listKey = species.map((s) => s.id).join(':')

    return (
        <div className="SpeciesPicker">
            <List key={listKey} className="SpeciesList">
                {species.map((sp, index) => itemContent(sp, index))}
            </List>
        </div>
    )
}

export default SpeciesPicker
