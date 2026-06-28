/* 可复用的检索练习小组件 (retrieval practice widget)
 * 用法:在课程 HTML 里写
 *   <div class="quiz" data-explain="为什么...">
 *     <p class="q">问题文本</p>
 *     <button class="opt" data-correct>正确答案</button>
 *     <button class="opt">干扰项</button>
 *     ...
 *   </div>
 * 点击后立即给出对/错反馈并显示解释。无依赖,纯前端。
 * 设计原则:即时反馈 = 尽可能紧的反馈环,建立长期记忆 (storage strength)。
 */
(function () {
  function wire(quiz) {
    var opts = quiz.querySelectorAll(".opt");
    var explain = quiz.getAttribute("data-explain");
    var feedback = document.createElement("p");
    feedback.className = "quiz-feedback";
    feedback.style.display = "none";
    quiz.appendChild(feedback);

    opts.forEach(function (btn) {
      btn.addEventListener("click", function () {
        var correct = btn.hasAttribute("data-correct");
        opts.forEach(function (b) {
          b.disabled = true;
          if (b.hasAttribute("data-correct")) b.classList.add("is-correct");
          else if (b === btn) b.classList.add("is-wrong");
        });
        feedback.textContent = (correct ? "✓ 答对了。 " : "✗ 再想想。 ") + (explain || "");
        feedback.className = "quiz-feedback " + (correct ? "ok" : "no");
        feedback.style.display = "block";
      });
    });
  }
  document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll(".quiz").forEach(wire);
  });
})();
