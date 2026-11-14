#include <TCanvas.h>
#include <TF1.h>
#include <TH1F.h>
#include <TRandom3.h>
#include <TVectorD.h>
#include <iostream>

void p1(){  // NOLINT
  // %% 01 定义直方图（基础对象创建）
  auto h = new TH1F("h", "gaus test", 100, -5, 5);  // NOLINT
  std::cout << "histogram created" << '\n';

  // %% 02 填充数据（多行块整段发送）
  TRandom3 rng(42);
  for (int i = 0; i < 10000; ++i) { h->Fill(rng.Gaus(0, 1)); }
  std::cout << "entries = " << h->GetEntries() << '\n';

  // %%
  auto c1 = new TCanvas("c1", "c1", 800, 600);  // NOLINT
  h->SetLineColor(kBlue);
  h->Draw();
  c1->Update();

  // %% 04 TVectorD
  TVectorD v(3);
  v[0] = 1;
  v[1] = 2;
  v[2] = 3;
  std::cout << "v*v = " << v * v << '\n';
  std::cout << "NormInf=" << v.NormInf() << " Norm1=" << v.Norm1() << '\n';

  // %% 05 lambda
  std::vector<double> xs = {1.1, 2.2, 3.3};
  double sum = 0;
  std::for_each(xs.begin(), xs.end(), [&](double x) { sum += x; });  // NOLINT
  std::cout << "sum = " << sum << '\n';

  // %% 06 undo
  auto dummy = new TF1("dummy", "gaus", -5, 5);  // NOLINT
  std::cout << "dummy created — 按 .undo 应撤销这条" << '\n';

  // %% 07 重启测试
  std::cout << "after restart: fresh kernel" << '\n';
}
