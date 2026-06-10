#include <functional>
#include <random>
#include <thread>
#include <Eigen/Eigen>

using namespace std;
using namespace Eigen;

MatrixXf rand_gen(int32_t row, int32_t col, float mean, float std)
{
    thread_local std::mt19937 engine(static_cast<uint32_t>(
        std::hash<std::thread::id>{}(std::this_thread::get_id())));
    std::normal_distribution<float> dist(mean, std);

    MatrixXf m(row, col);
    for (int32_t r = 0; r < row; ++r) {
        for (int32_t c = 0; c < col; ++c) {
            m(r, c) = dist(engine);
        }
    }
    return m;
}

