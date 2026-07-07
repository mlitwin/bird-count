import {
    Taxonomy,
    Checklist,
    Observation,
    ObservationLocation,
} from '../model/types'

import { v4 as uuidv4 } from 'uuid'

const currentLocation: ObservationLocation = new ObservationLocation()

;(() => {
    const options = {}

    function success(pos: GeolocationPosition) {
        const crd = pos.coords
        currentLocation.latitude = crd.latitude
        currentLocation.longitude = crd.longitude
    }

    function error(err) {
        console.error(`ERROR(${err.code}): ${err.message}`)
    }

    try {
        navigator.geolocation.watchPosition(success, error, options)
    } catch (e) {}
})()

class AppContext {
    constructor() {
        this.taxonomy = null
        this.checklist = null
    }
    getCurrentLocation() {
        return currentLocation
    }
    createObservation(): Observation {
        const now = Date.now()

        const ret = new Observation()
        ret.id = uuidv4()
        ret.createdAt = now
        ret.start = now
        ret.duration = 0
        ret.location = this.getCurrentLocation()
        ret.taxonomy = this.taxonomy
        ret.species = null
        ret.count = 0
        ret.parent = null

        return ret
    }
    ready() {
        return this.taxonomy != null && this.checklist != null
    }
    taxonomy: Taxonomy
    checklist: Checklist
}

export default AppContext
