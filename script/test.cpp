// harper:ignore
// test.cpp — rslime.nvim test file
// Usage: open this file in nvim → ,r0s to start the ROOT REPL → cursor inside a cell + ,r0k to send
// ,r0a runs all cells in order (wrapper structure is skipped automatically)
// ,r0R restarts the kernel, ,r0u undoes the last cling transaction
#include <TCanvas.h>
#include <TF1.h>
#include <TH1F.h>
#include <TRandom3.h>
#include <TVectorD.h>
#include <iostream>
#include <vector>
void p1() {
  // %% 01 create a histogram (basic object creation)
  auto h = new TH1F("h", "gaus test", 100, -5, 5);
  std::cout << "histogram created" << std::endl;
  double c = 3;
  auto d = c + 4;

  // %% 02 fill data (multi-line block sent as a whole)
  TRandom3 rng(42);
  for (int i = 0; i < 10000; ++i) { h->Fill(rng.Gaus(0, 1)); }
  std::cout << "entries = " << h->GetEntries() << std::endl;

  // %% 03 draw (new canvas + draw)
  auto c1 = new TCanvas("c1", "c1", 800, 600);
  h->SetLineColor(kBlue);
  h->Draw();
  c1->Update();

  // %% 04 TVectorD math
  TVectorD v(3);
  v[0] = 1;
  v[1] = 2;
  v[2] = 3;
  std::cout << "v*v = " << v * v << std::endl;
  std::cout << "NormInf=" << v.NormInf() << " Norm1=" << v.Norm1() << std::endl;

  // %% 05 lambda / STL (modern C++ support in cling)
  std::vector<double> xs = {1.1, 2.2, 3.3};
  double sum = 0;
  std::for_each(xs.begin(), xs.end(), [&](double x) -> void { sum += x; });
  std::cout << "sum = " << sum << std::endl;

  // %% 06 undo test
  auto dummy = new TF1("dummy", "gaus", -5, 5);  // NOLINT
  std::cout << "dummy created — press ,r0u to undo this line" << std::endl;

  // %% 07 restart test
  std::cout << "after restart: fresh kernel" << std::endl;
}
