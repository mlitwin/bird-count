import Taxonomy from './taxonomy'
import Species from './species'

function nameToAbbreviation(name: any): string {
    return name
        .toUpperCase()
        .replaceAll(/[^-A-Za-z /]/g, '')
        .replaceAll(/[^A-Za-z]/g, ' ')
        .split(/\s+/)
        .map((w) => w[0])
        .join('')
}

function addAbbreviations(species) {
    let abbrv = []
    const commonName = species.localizations.en.commonName.toUpperCase()
    const sciName = species.sciName

    abbrv.push(nameToAbbreviation(commonName), nameToAbbreviation(sciName))
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
            addAbbreviations(chsp)
            this.species.push(chsp)
        }
    }
}

export default Checklist
