import React from 'react'
import Button from '@mui/material/Button'
import ButtonGroup from '@mui/material/ButtonGroup'
import './SpeciesNavigation.css'

function SpeciesNavigation(props) {
    function changeActiveSpecies(delta) {
        props.changeActive(delta)
    }

    return (
        <div className="SpeciesNavigation">
            <ButtonGroup>
                <Button onClick={() => changeActiveSpecies(-1)}>↑</Button>
                <Button onClick={() => changeActiveSpecies(1)}>↓</Button>
            </ButtonGroup>
        </div>
    )
}

export default SpeciesNavigation
