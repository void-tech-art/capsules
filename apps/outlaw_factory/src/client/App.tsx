import * as React from "react";
import { BrowserRouter as Router, Routes, Route } from "react-router-dom";
import HashPage from "./detailPage";
import TextInputWithButton from "./Input";
import SignInButton from "./wallet.";

const App = (props: AppProps) => {
  return (
    <main className="container my-5">
      <div className="navbar">
        <SignInButton/>
      </div>
      <Router>
        <h1 className="text-primary text-center">
          Capsule craft - Art generation
        </h1>
        <Routes>
          <Route path="/" element={<TextInputWithButton />} />
          <Route path="/hash/:hash" element={<HashPage />} />
        </Routes>
      </Router>
    </main>
  );
};

interface AppProps {}

export default App;
