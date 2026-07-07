import Species from './species'

class Taxonomy {
    id: string
    species: Species[]

    speciesTaxons: { [id: string]: Species }
    constructor(id: string) {
        this.id = id
        this.speciesTaxons = {}
    }
    addSpecies(species: Species[]) {
        this.species = species

        this.species.forEach((sp) => {
            this.speciesTaxons[sp.id] = sp
        })
    }

    commonAncestor(a: Species, b: Species): Species {
        let o = a
        const marked = {}
        while (o) {
            marked[o.id] = true
            o = this.speciesTaxons[o.parent]
        }
        o = b
        while (o) {
            if (marked[o.id]) {
                return o
            }
            o = this.speciesTaxons[o.parent]
        }
        // notreached
    }

    speciesTaxon(taxon: Species): Species {
        let sp = taxon
        while (sp.type !== 'species') {
            if (sp.parent === null) {
                return taxon
            }
            sp = this.speciesTaxons[sp.parent]
        }
        return sp
    }
}

export default Taxonomy
