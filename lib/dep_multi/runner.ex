defmodule DepMulti.Runner do
  def run(operations, worker_id) do
    IO.puts(inspect(operations))
    # CourseDeployments.repos_for_course(course_params)
    #   |> Enum.map(&deploy_student_repo(&1, worker_pid))
    #   |> Enum.map(&update_processing_state(&1, worker_pid))
  end

  # def deploy_student_repo(canonical_repo, worker_pid) do
  #   {:ok, pid} = StudentRepoSupervisor.start_work(canonical_repo, worker_pid)
  #   pid
  # end
  #
  # def update_processing_state(student_repo_pid, worker_pid) do
  #   CourseWorker.update_processing_state(student_repo_pid, worker_pid)
  # end
end
