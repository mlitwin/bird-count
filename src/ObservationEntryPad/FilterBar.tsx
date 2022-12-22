import React from 'react'
import Slider from '@mui/material/Slider'

import './FilterBar.css'

/*
    0: Never,
    1: Scarce
    2: Uncommon,
    3: Common
*/

function FilterBar(props) {
    function handleChange(_e, value) {
        const newFilter = { ...props.filter }
        newFilter.commonness = 3 - value
        props.setFilter(newFilter)
    }
    return (
        <div className="KeypadControls">
            <Slider
                className="Commonness"
                size="small"
                defaultValue={0}
                value={3 - props.filter.commonness}
                onChange={handleChange}
                valueLabelDisplay="auto"
                step={1}
                marks
                min={0}
                max={3}
            />

            <div className="FilterValue">
                <div>{props.filter.text}</div>
            </div>
        </div>
    )
}

export default FilterBar
