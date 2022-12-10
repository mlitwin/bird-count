import Taxonomy from './taxonomy'
import Species from './species'

function addAbbeviations(species) {
    let abbrv = []
    const commonName = species.localizations.en.commonName.toUpperCase()

    const name = commonName
        .replaceAll(/[^-A-Za-z /]/g, '')
        .replaceAll(/[^A-Za-z]/g, ' ')
        .split(/\s+/)
        .map((w) => w[0])
        .join('')

    abbrv.push(name)
    species.abbreviations = abbrv
}

function testFilter(sp) {
    switch (sp.type) {
        case 'hybrid':
        case 'slash':
        case 'issf':
        case 'intergrade':
        case 'form':
            return false
    }

    return true
}

class Checklist {
    taxonomy: Taxonomy

    species: Species[]

    constructor(taxonomy: Taxonomy) {
        this.taxonomy = taxonomy
        this.species = []
    }

    setFilters(filters: any) {
        for (let id in filters.species) {
            const sp = filters.species[id]
            const tax = this.taxonomy.speciesTaxons[id]
            let chsp = { ...tax, ...sp }
            chsp.standard = testFilter(chsp)
            addAbbeviations(chsp)
            this.species.push(chsp)
        }
    }
}

export default Checklist
