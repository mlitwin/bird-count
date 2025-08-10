import React from 'react'
import ReactDOM from 'react-dom/client'
import './index.css'
import { App } from './App'

const documentHeight = () => {
    const doc = document.documentElement
    doc.style.setProperty('--doc-height', `${window.innerHeight}px`)
}
window.addEventListener('resize orientationchange', documentHeight)
documentHeight()

const rootEl = document.getElementById('root')!
const root = ReactDOM.createRoot(rootEl)
root.render(
    <React.StrictMode>
        <App />
    </React.StrictMode>
)
