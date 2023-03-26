import React from 'react'

import './FilterBar.css'

function FilterBar(props) {
    const showPrompt = props.filter.text === ''
    const text = showPrompt ? 'Search' : props.filter.text
    return (
        <div className="KeypadControls">
            <div className={'FilterValue' + (showPrompt ? ' prompt' : '')}>
                <div>{text}</div>
            </div>
        </div>
    )
}

export default FilterBar
