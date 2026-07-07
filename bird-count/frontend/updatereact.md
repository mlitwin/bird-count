# React Upgrade Plan

Goal: Upgrade React stack (currently React 18.2 + CRA 5 + TS 4.8) to latest (React 19 + modern build tooling) with minimal downtime.

## 1. Preparation
- Create branch: `upgrade/react19`.
- Record current dependency tree: `npm ls > docs/deps-pre-upgrade.txt`.
- Add/commit lockfile if missing.
- Ensure Node >= 18.18 (prefer 20 LTS). Update `.nvmrc` (add if absent).

## 2. Dependency Audit
- Remove unused deps (scan imports): emotion, MUI ok; confirm `teaful` usage.
- Add `@types/react-dom` removal (React 19 includes types in root packages when using new types?). Keep for now; remove after upgrade if redundant.

## 3. Choose Build Tool
Option A (minimal): Stay on CRA 5 (still webpack 5) – limited benefit; cannot leverage new optimizations easily.
Option B (recommended): Migrate to Vite (faster dev, smaller config).
Proceed with B.

## 4. Incremental Migration to Vite
- Install: `npm i -D vite @vitejs/plugin-react`.
- Create `vite.config.ts` with React plugin + `base: '/bird-count'` for GitHub Pages.
- Move `index.html` from `public/` root to project root (adjust `%PUBLIC_URL%` -> `/bird-count`).
- Replace CRA env vars: `REACT_APP_` => `VITE_`.
- Update scripts: `dev`, `build`, `preview`, keep `deploy` (point to `dist`).
- Update `gh-pages` deploy path `dist`.
- Handle assets: copy existing `public/manifest.json`, icons into root or keep `public/` and reference.

## 5. TypeScript + Tooling
- Upgrade TS: `npm i -D typescript@^5.5`.
- Add `tsconfig.node.json` if needed for Vite.
- Adjust `tsconfig.json` target: `ES2022`, `moduleResolution: node16`.

## 6. React 19 Upgrade
- `npm i react@^19 react-dom@^19`.
- Upgrade types: `@types/react@^19 @types/react-dom@^19` (if still separate).
- Replace legacy `ReactDOM.render` (already using 18 root API) – confirm usage of `createRoot`.
- Enable `StrictMode` (already? verify) to surface issues.

## 7. Library Upgrades
- MUI: upgrade to latest v5 minor or v6 if GA (`@mui/material @mui/icons-material @emotion/*`). Follow MUI migration notes.
- RxJS: check latest 7.x minor; upgrade.
- `react-simple-keyboard`, `react-virtuoso` update to latest majors (check breaking changes).
- Testing libs: `@testing-library/*` to latest; update jest DOM matchers.

## 8. Codebase Adjustments
- Search for deprecated React 19 patterns: legacy context, UNSAFE_ lifecycles (likely none in functional code).
- Verify Suspense usage (if any) – new behaviors.
- Adjust any `act()` warnings in tests (React 19 stricter event batching).
- Update imports for MUI v6 (if changed). Run codemods where provided.

## 9. Environment Variables
- Rename `REACT_APP_*` -> `VITE_*`.
- Update references in code: `process.env.REACT_APP_X` -> `import.meta.env.VITE_X`.

## 10. Linting/Formatting
- Add ESLint config for Vite + TypeScript (replace CRA preset). Install `eslint @typescript-eslint/* eslint-plugin-react-hooks`.
- Add Prettier config if desired.

## 11. Testing Adjustments
- Replace CRA test script with `vitest` (optional) or keep Jest initially.
- If switching: install `vitest @vitest/ui jsdom @testing-library/jest-dom` and add `setupTests.ts` for jest-dom.
- Update `package.json` test script: `vitest --ui` (or `vitest run`).

## 12. Build + Deploy
- Update `deploy` script: `gh-pages -d dist`.
- Run `npm run build` then `npx serve dist` (or `vite preview`) locally.
- Deploy to GH Pages and validate assets paths (404 check for CSS/JS).

## 13. Performance Checks
- Lighthouse against production (before & after) – record metrics.
- Bundle analysis: add `rollup-plugin-visualizer` or `source-map-explorer` pre/post.

## 14. Cleanup
- Remove CRA-specific files: `reportWebVitals.tsx` (optional), service worker specifics if unused.
- Remove `react-scripts` from dependencies.
- Remove leftover `public/` not needed.

## 15. Validation
- Cross-browser smoke test (Chrome, Firefox, Safari mobile).
- Ensure keyboard / swipe interactions still work.
- Confirm dynamic imports (if any) still lazy-load.

## 16. Rollback Plan
- Keep the branch unmerged until all tests pass and deployment verified.
- Tag pre-upgrade commit: `git tag pre-react19`.

## 17. Timeline (Suggested)
- Day 1: Prep, Vite baseline, TS upgrade.
- Day 2: React 19 + library upgrades, fix build/test issues.
- Day 3: Optimize, clean, deploy, document.

## 18. Documentation
- Update README (dev server commands, env var names).
- Add CHANGELOG entry summarizing upgrade.

## 19. Open Questions
- Keep Jest vs move to Vitest now? (decide early)
- Adopt React Server Components? (defer unless needed)
- Introduce code splitting metrics? (optional).

## 20. Success Criteria
- All tests green.
- No runtime console errors/warnings in StrictMode.
- Bundle size not increased (>5%).
- Deployment works at GitHub Pages path.

(End)