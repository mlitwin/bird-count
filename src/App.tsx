import React, { useState, useEffect } from 'react'
import './App.css'
import Tabs from '@mui/material/Tabs'
import Tab from '@mui/material/Tab'

import ObservationEntryPad from './ObservationEntryPad'
import ObservationHistory from './ObservationHistory'
import { useAppContext } from 'store/store'

function App() {
    const [value, setValue] = React.useState(0)
    const appContext = useAppContext()

    const handleChange = (event: React.SyntheticEvent, newValue: number) => {
        setValue(newValue)
    }

    function appContentHTML() {
        if (!appContext.ready()) {
            return <React.Fragment>...</React.Fragment>
        }

        return (
            <React.Fragment>
                <div hidden={value !== 0}>
                    <ObservationEntryPad />
                </div>
                <div hidden={value !== 1}>
                    <ObservationHistory />
                </div>
            </React.Fragment>
        )
    }

    return (
        <div className="App">
            <Tabs
                variant="fullWidth"
                className="AppHeader"
                value={value}
                onChange={handleChange}
            >
                <Tab label="Home" />
                <Tab label="History" />
            </Tabs>
            <div className="AppContent">{appContentHTML()}</div>
        </div>
    )
}

export { App }
