import React from 'react'
import './App.css'
import IconButton from '@mui/material/IconButton'
import { SettingsOutlined } from '@mui/icons-material'
import Tabs from '@mui/material/Tabs'
import Tab from '@mui/material/Tab'

import ObservationEntryPad from './ObservationEntryPad'
import ObservationHistory from './ObservationHistory'
import Settings from './Settings'
import { useAppContext } from 'store/store'

function App() {
    const [value, setValue] = React.useState(0)
    const [settingsOpen, setSettingsOpen] = React.useState(false)
    const [commonnessSetting, setCommonnessSetting] = React.useState(2)
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
                    <ObservationEntryPad
                        commonnessSetting={commonnessSetting}
                    />
                </div>
                <div hidden={value !== 1}>
                    <ObservationHistory mode="summary" />
                </div>
                <div hidden={value !== 2}>
                    <ObservationHistory mode="log" />
                </div>
            </React.Fragment>
        )
    }

    return (
        <div className="App">
            <Settings
                open={settingsOpen}
                setOpen={setSettingsOpen}
                commonnessSetting={commonnessSetting}
                setCommonnessSetting={setCommonnessSetting}
            ></Settings>
            <div className="AppNav">
                <div className="AppHeaderContainer">
                    <Tabs
                        variant="fullWidth"
                        className="AppHeader"
                        value={value}
                        onChange={handleChange}
                    >
                        <Tab label="Home" />
                        <Tab label="Summary" />
                        <Tab label="Log" />
                    </Tabs>
                </div>
                <IconButton
                    className="Button"
                    onClick={() => setSettingsOpen(true)}
                >
                    <SettingsOutlined fontSize="large" />
                </IconButton>
            </div>
            <div className="AppContent">{appContentHTML()}</div>
        </div>
    )
}

export { App }
