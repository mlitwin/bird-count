function Species(props) {
    const species = props.species;
    const speciesName = species ? species.name : '';

    return (
        <span>{speciesName}</span>
    )
}

export default Species;