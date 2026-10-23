// Лабораторная работа 7 — CI/CD pipeline для OpenBMC
// Stages: QEMU → API tests → WebUI tests → Locust load test
// Проект смонтирован в контейнер как /workspace (см. docker-compose.jenkins.yml)

pipeline {
  agent { label 'built-in' }

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '10'))
    timeout(time: 45, unit: 'MINUTES')
  }

  environment {
    BMC_URL           = 'https://127.0.0.1:2443'
    BMC_USER          = 'root'
    BMC_PASSWORD      = '0penBmc'
    OPENBMC_WEBUI_URL = 'https://127.0.0.1:2443'
    OPENBMC_USERNAME  = 'root'
    OPENBMC_PASSWORD  = '0penBmc'
    LOCUST_USERS      = '5'
    LOCUST_SPAWN_RATE = '1'
    LOCUST_RUNTIME    = '30s'
    RUN_POWER_TEST    = '1'
    RUN_SELENIUM_WEBUI = '0'
  }

  stages {
    stage('Checkout') {
      steps {
        dir('/workspace') {
          echo "Workspace dir=/workspace (Jenkins WORKSPACE=${env.WORKSPACE})"
          sh '''
            set -eux
            pwd
            ls -la
            test -f Jenkinsfile
            test -f test_redfish.py
            test -f locustfile.py
            test -f openbmc_auth_tests.py
            test -f test_webui_smoke.py
            chmod +x ci/scripts/*.sh
          '''
        }
      }
    }

    stage('Start OpenBMC (QEMU)') {
      steps {
        dir('/workspace') {
          sh './ci/scripts/start_qemu.sh'
        }
      }
      post {
        always {
          dir('/workspace') {
            archiveArtifacts artifacts: 'ci-reports/qemu/**', allowEmptyArchive: true, fingerprint: true
          }
        }
      }
    }

    stage('API Autotests (Redfish/PyTest)') {
      steps {
        dir('/workspace') {
          catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
            sh './ci/scripts/run_api_tests.sh'
          }
        }
      }
      post {
        always {
          dir('/workspace') {
            junit allowEmptyResults: true, testResults: 'ci-reports/api/junit.xml'
            archiveArtifacts artifacts: 'ci-reports/api/**', allowEmptyArchive: true, fingerprint: true
          }
        }
      }
    }

    stage('WebUI Tests') {
      steps {
        dir('/workspace') {
          catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
            sh './ci/scripts/run_webui_tests.sh'
          }
        }
      }
      post {
        always {
          dir('/workspace') {
            junit allowEmptyResults: true, testResults: 'ci-reports/webui/junit*.xml'
            archiveArtifacts artifacts: 'ci-reports/webui/**', allowEmptyArchive: true, fingerprint: true
          }
        }
      }
    }

    stage('Load Testing (Locust)') {
      steps {
        dir('/workspace') {
          catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
            sh './ci/scripts/run_locust.sh'
          }
        }
      }
      post {
        always {
          dir('/workspace') {
            archiveArtifacts artifacts: 'ci-reports/locust/**', allowEmptyArchive: true, fingerprint: true
          }
        }
      }
    }
  }

  post {
    always {
      dir('/workspace') {
        sh '''
          set +e
          ./ci/scripts/stop_qemu.sh || true
          mkdir -p ci-reports
          echo "Pipeline finished at $(date -Is)" | tee ci-reports/pipeline_footer.txt
        '''
        archiveArtifacts artifacts: 'ci-reports/pipeline_footer.txt', allowEmptyArchive: true
      }
    }
    success {
      echo 'OpenBMC CI/CD pipeline SUCCEEDED'
    }
    unstable {
      echo 'Pipeline UNSTABLE — артефакты ci-reports/* сохранены'
    }
    failure {
      echo 'Pipeline FAILED — смотрите логи stage и артефакты ci-reports/'
    }
  }
}
