import React from 'react'
import ReactDOM from 'react-dom/client'
import './index.css'
import { App } from './App'
import reportWebVitals from './reportWebVitals'

const documentHeight = () => {
    const doc = document.documentElement
    doc.style.setProperty('--doc-height', `${window.innerHeight}px`)
}
window.addEventListener('resize orientationchange', documentHeight)
documentHeight()

const root = ReactDOM.createRoot(document.getElementById('root'))
root.render(
    <React.StrictMode>
        <App />
    </React.StrictMode>
)

// If you want to start measuring performance in your app, pass a function
// to log results (for example: reportWebVitals(console.log))
// or send to an analytics endpoint. Learn more: https://bit.ly/CRA-vitals
reportWebVitals(null)
