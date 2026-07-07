import XCTest

final class ScreenshotTests: XCTestCase {
    var app: XCUIApplication!
    
    @MainActor
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        setupSnapshot(app)
        app.launch()
        
        // Give the app time to load completely
        sleep(3)
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    @MainActor
    func testGenerateScreenshots() throws {
        // Wait for any UI element to appear - this is a very basic test
        let timeout: TimeInterval = 15.0
        
        // Try to find any basic UI element
        var appLaunched = false
        let possibleElements = [
            app.navigationBars.firstMatch,
            app.buttons.firstMatch,
            app.staticTexts.firstMatch,
            app.otherElements.firstMatch
        ]
        
        for element in possibleElements {
            if element.waitForExistence(timeout: timeout) {
                appLaunched = true
                break
            }
        }
        
        // Even if we can't find specific elements, try to take screenshots
        // This should work as long as the app launches
        XCTAssertTrue(appLaunched, "App should launch with some UI elements")
        
        // Take screenshots with generous delays
        snapshot("01_MainView")
        sleep(3)
        
        // Try to interact with search if possible
        let searchFields = app.searchFields
        if searchFields.count > 0 {
            let searchField = searchFields.firstMatch
            if searchField.exists {
                searchField.tap()
                searchField.typeText("robin")
                sleep(2)
                snapshot("02_SearchView")
                
                // Clear search
                let clearButton = app.buttons["Clear text"]
                if clearButton.exists {
                    clearButton.tap()
                }
            }
        }
        
        sleep(2)
        snapshot("03_FinalView")
    }
}