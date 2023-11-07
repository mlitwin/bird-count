import React from 'react'

function SpeciesName(props) {
    const species = props.species
    const speciesName = species ? species.localizations.en.commonName : ''
    const sciName = species ? species.sciName : ''

    return (
        <div className="SpeciesEntry">
            <div className="CommonName">{speciesName}</div>
            <div className="SciName">{sciName}</div>
        </div>
    )
}

export default SpeciesName
