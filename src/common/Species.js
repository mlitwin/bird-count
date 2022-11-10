
function Species(props) {

    const species = props.species;
    const speciesName = species ? species.localizations.en.commonName : '';

    return (
        <span>{speciesName}</span>
    )
}

export default Species;