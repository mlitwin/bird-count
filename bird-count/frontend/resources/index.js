import fs from "fs";
import { favicons } from "favicons";

const source = "logo.png";

const configuration = {
    appName: "Bird Count"
}

async function generate() {

try {
    const response = await favicons(source, configuration);
  
  //  console.log(response.images); // Array of { name: string, contents: <buffer> }
   // console.log(response.files); // Array of { name: string, contents: <string> }
   // console.log(response.html); // Array of strings (html elements)
   const favicon = response.images[0];
   fs.writeFileSync('favicon.ico', favicon.contents);
  } catch (error) {
    console.log(error.message); // Error description e.g. "An unknown error has occurred"
  }
}

generate();
