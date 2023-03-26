import Taxonomy from './taxonomy'
import ObservationLocation from './location'

class Observation {
    id: string
    createdAt: number
    start: number
    duration: number
    location: ObservationLocation
    taxonomy: Taxonomy
    species: any
    count: number
    parent: null | Observation
    children?: Observation[]

    toJSONObject(): object {
        return {
            id: this.id,
            createdAt: this.createdAt,
            start: this.start,
            duration: this.duration,
            location: this.location,
            taxonomy: this.taxonomy.id,
            species: this.species.id,
            count: this.count,
            parent: this.parent ? this.parent.id : null,
        }
    }

    fromJSONObject(taxonomy: Taxonomy, json: any) {
        this.id = json.id
        this.createdAt = json.createdAt
        this.start = json.start
        this.duration = json.duration
        this.location = json.location
            ? json.location
            : { latitude: NaN, longitude: NaN }
        this.taxonomy = taxonomy
        this.species = taxonomy.speciesTaxons[json.species]
        this.count = json.count
        this.parent = null
    }

    Assign(obs: Observation) {
        this.id = obs.id
        this.createdAt = obs.createdAt
        this.start = obs.start
        this.duration = obs.duration
        this.location = obs.location
        this.taxonomy = obs.taxonomy
        this.species = obs.species
        this.count = obs.count
        this.parent = obs.parent
    }

    Union(taxonomy: Taxonomy, obs: Observation) {
        const thisend = this.start + this.duration
        const thatend = obs.start + obs.duration
        if (obs.start < this.start) {
            this.start = obs.start
        }
        const end = thisend > thatend ? thisend : thatend

        if (this.location && obs.location) {
            this.location.latitude =
                (this.location.latitude + obs.location.latitude) / 2
            this.location.longitude =
                (this.location.longitude + obs.location.longitude) / 2
        }

        this.duration = end - this.start
        this.species = taxonomy.commonAncestor(this.species, obs.species)
        this.count += obs.count
    }

    UnionWithDescendent(obs: Observation) {
        this.count += obs.count
    }
}

export default Observation
